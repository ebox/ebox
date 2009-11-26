/* 
   Unix SMB/CIFS implementation.
   client file operations
   Copyright (C) Andrew Tridgell 1994-1998
   Copyright (C) Jeremy Allison 2001-2002
   
   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 3 of the License, or
   (at your option) any later version.
   
   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.
   
   You should have received a copy of the GNU General Public License
   along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include "includes.h"

/****************************************************************************
 Hard/Symlink a file (UNIX extensions).
 Creates new name (sym)linked to oldname.
****************************************************************************/

static bool cli_link_internal(struct cli_state *cli, const char *oldname, const char *newname, bool hard_link)
{
	unsigned int data_len = 0;
	unsigned int param_len = 0;
	uint16 setup = TRANSACT2_SETPATHINFO;
	char *param;
	char *data;
	char *rparam=NULL, *rdata=NULL;
	char *p;
	size_t oldlen = 2*(strlen(oldname)+1);
	size_t newlen = 2*(strlen(newname)+1);

	param = SMB_MALLOC_ARRAY(char, 6+newlen+2);

	if (!param) {
		return false;
	}

	data = SMB_MALLOC_ARRAY(char, oldlen+2);

	if (!data) {
		SAFE_FREE(param);
		return false;
	}

	SSVAL(param,0,hard_link ? SMB_SET_FILE_UNIX_HLINK : SMB_SET_FILE_UNIX_LINK);
	SIVAL(param,2,0);
	p = &param[6];

	p += clistr_push(cli, p, newname, newlen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	p = data;
	p += clistr_push(cli, p, oldname, oldlen, STR_TERMINATE);
	data_len = PTR_DIFF(p, data);

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		SAFE_FREE(data);
		SAFE_FREE(param);
		return false;
	}

	SAFE_FREE(data);
	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
			return false;
	}

	SAFE_FREE(data);
	SAFE_FREE(param);
	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return true;
}

/****************************************************************************
 Map standard UNIX permissions onto wire representations.
****************************************************************************/

uint32 unix_perms_to_wire(mode_t perms)
{
        unsigned int ret = 0;

        ret |= ((perms & S_IXOTH) ?  UNIX_X_OTH : 0);
        ret |= ((perms & S_IWOTH) ?  UNIX_W_OTH : 0);
        ret |= ((perms & S_IROTH) ?  UNIX_R_OTH : 0);
        ret |= ((perms & S_IXGRP) ?  UNIX_X_GRP : 0);
        ret |= ((perms & S_IWGRP) ?  UNIX_W_GRP : 0);
        ret |= ((perms & S_IRGRP) ?  UNIX_R_GRP : 0);
        ret |= ((perms & S_IXUSR) ?  UNIX_X_USR : 0);
        ret |= ((perms & S_IWUSR) ?  UNIX_W_USR : 0);
        ret |= ((perms & S_IRUSR) ?  UNIX_R_USR : 0);
#ifdef S_ISVTX
        ret |= ((perms & S_ISVTX) ?  UNIX_STICKY : 0);
#endif
#ifdef S_ISGID
        ret |= ((perms & S_ISGID) ?  UNIX_SET_GID : 0);
#endif
#ifdef S_ISUID
        ret |= ((perms & S_ISUID) ?  UNIX_SET_UID : 0);
#endif
        return ret;
}

/****************************************************************************
 Map wire permissions to standard UNIX.
****************************************************************************/

mode_t wire_perms_to_unix(uint32 perms)
{
        mode_t ret = (mode_t)0;

        ret |= ((perms & UNIX_X_OTH) ? S_IXOTH : 0);
        ret |= ((perms & UNIX_W_OTH) ? S_IWOTH : 0);
        ret |= ((perms & UNIX_R_OTH) ? S_IROTH : 0);
        ret |= ((perms & UNIX_X_GRP) ? S_IXGRP : 0);
        ret |= ((perms & UNIX_W_GRP) ? S_IWGRP : 0);
        ret |= ((perms & UNIX_R_GRP) ? S_IRGRP : 0);
        ret |= ((perms & UNIX_X_USR) ? S_IXUSR : 0);
        ret |= ((perms & UNIX_W_USR) ? S_IWUSR : 0);
        ret |= ((perms & UNIX_R_USR) ? S_IRUSR : 0);
#ifdef S_ISVTX
        ret |= ((perms & UNIX_STICKY) ? S_ISVTX : 0);
#endif
#ifdef S_ISGID
        ret |= ((perms & UNIX_SET_GID) ? S_ISGID : 0);
#endif
#ifdef S_ISUID
        ret |= ((perms & UNIX_SET_UID) ? S_ISUID : 0);
#endif
        return ret;
}

/****************************************************************************
 Return the file type from the wire filetype for UNIX extensions.
****************************************************************************/

static mode_t unix_filetype_from_wire(uint32 wire_type)
{
	switch (wire_type) {
		case UNIX_TYPE_FILE:
			return S_IFREG;
		case UNIX_TYPE_DIR:
			return S_IFDIR;
#ifdef S_IFLNK
		case UNIX_TYPE_SYMLINK:
			return S_IFLNK;
#endif
#ifdef S_IFCHR
		case UNIX_TYPE_CHARDEV:
			return S_IFCHR;
#endif
#ifdef S_IFBLK
		case UNIX_TYPE_BLKDEV:
			return S_IFBLK;
#endif
#ifdef S_IFIFO
		case UNIX_TYPE_FIFO:
			return S_IFIFO;
#endif
#ifdef S_IFSOCK
		case UNIX_TYPE_SOCKET:
			return S_IFSOCK;
#endif
		default:
			return (mode_t)0;
	}
}

/****************************************************************************
 Do a POSIX getfacl (UNIX extensions).
****************************************************************************/

bool cli_unix_getfacl(struct cli_state *cli, const char *name, size_t *prb_size, char **retbuf)
{
	unsigned int param_len = 0;
	unsigned int data_len = 0;
	uint16 setup = TRANSACT2_QPATHINFO;
	char *param;
	size_t nlen = 2*(strlen(name)+1);
	char *rparam=NULL, *rdata=NULL;
	char *p;

	param = SMB_MALLOC_ARRAY(char, 6+nlen+2);
	if (!param) {
		return false;
	}

	p = param;
	memset(p, '\0', 6);
	SSVAL(p, 0, SMB_QUERY_POSIX_ACL);
	p += 6;
	p += clistr_push(cli, p, name, nlen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	if (!cli_send_trans(cli, SMBtrans2,
		NULL,                        /* name */
		-1, 0,                       /* fid, flags */
		&setup, 1, 0,                /* setup, length, max */
		param, param_len, 2,         /* param, length, max */
		NULL,  0, cli->max_xmit      /* data, length, max */
		)) {
		SAFE_FREE(param);
		return false;
	}

	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
		return false;
	}

	if (data_len < 6) {
		SAFE_FREE(rdata);
		SAFE_FREE(rparam);
		return false;
	}

	SAFE_FREE(rparam);
	*retbuf = rdata;
	*prb_size = (size_t)data_len;

	return true;
}

/****************************************************************************
 Stat a file (UNIX extensions).
****************************************************************************/

bool cli_unix_stat(struct cli_state *cli, const char *name, SMB_STRUCT_STAT *sbuf)
{
	unsigned int param_len = 0;
	unsigned int data_len = 0;
	uint16 setup = TRANSACT2_QPATHINFO;
	char *param;
	size_t nlen = 2*(strlen(name)+1);
	char *rparam=NULL, *rdata=NULL;
	char *p;

	ZERO_STRUCTP(sbuf);

	param = SMB_MALLOC_ARRAY(char, 6+nlen+2);
	if (!param) {
		return false;
	}
	p = param;
	memset(p, '\0', 6);
	SSVAL(p, 0, SMB_QUERY_FILE_UNIX_BASIC);
	p += 6;
	p += clistr_push(cli, p, name, nlen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                       /* fid, flags */
			&setup, 1, 0,                /* setup, length, max */
			param, param_len, 2,         /* param, length, max */
			NULL,  0, cli->max_xmit      /* data, length, max */
			)) {
		SAFE_FREE(param);
		return false;
	}

	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
		return false;
	}

	if (data_len < 96) {
		SAFE_FREE(rdata);
		SAFE_FREE(rparam);
		return false;
	}

	sbuf->st_size = IVAL2_TO_SMB_BIG_UINT(rdata,0);     /* total size, in bytes */
	sbuf->st_blocks = IVAL2_TO_SMB_BIG_UINT(rdata,8);   /* number of blocks allocated */
#if defined (HAVE_STAT_ST_BLOCKS) && defined(STAT_ST_BLOCKSIZE)
	sbuf->st_blocks /= STAT_ST_BLOCKSIZE;
#else
	/* assume 512 byte blocks */
	sbuf->st_blocks /= 512;
#endif
	set_ctimespec(sbuf, interpret_long_date(rdata + 16));    /* time of last change */
	set_atimespec(sbuf, interpret_long_date(rdata + 24));    /* time of last access */
	set_mtimespec(sbuf, interpret_long_date(rdata + 32));    /* time of last modification */

	sbuf->st_uid = (uid_t) IVAL(rdata,40);      /* user ID of owner */
	sbuf->st_gid = (gid_t) IVAL(rdata,48);      /* group ID of owner */
	sbuf->st_mode = unix_filetype_from_wire(IVAL(rdata, 56));
#if defined(HAVE_MAKEDEV)
	{
		uint32 dev_major = IVAL(rdata,60);
		uint32 dev_minor = IVAL(rdata,68);
		sbuf->st_rdev = makedev(dev_major, dev_minor);
	}
#endif
	sbuf->st_ino = (SMB_INO_T)IVAL2_TO_SMB_BIG_UINT(rdata,76);      /* inode */
	sbuf->st_mode |= wire_perms_to_unix(IVAL(rdata,84));     /* protection */
	sbuf->st_nlink = IVAL(rdata,92);    /* number of hard links */

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return true;
}

/****************************************************************************
 Symlink a file (UNIX extensions).
****************************************************************************/

bool cli_unix_symlink(struct cli_state *cli, const char *oldname, const char *newname)
{
	return cli_link_internal(cli, oldname, newname, False);
}

/****************************************************************************
 Hard a file (UNIX extensions).
****************************************************************************/

bool cli_unix_hardlink(struct cli_state *cli, const char *oldname, const char *newname)
{
	return cli_link_internal(cli, oldname, newname, True);
}

/****************************************************************************
 Chmod or chown a file internal (UNIX extensions).
****************************************************************************/

static bool cli_unix_chmod_chown_internal(struct cli_state *cli, const char *fname, uint32 mode, uint32 uid, uint32 gid)
{
	unsigned int data_len = 0;
	unsigned int param_len = 0;
	uint16 setup = TRANSACT2_SETPATHINFO;
	size_t nlen = 2*(strlen(fname)+1);
	char *param;
	char data[100];
	char *rparam=NULL, *rdata=NULL;
	char *p;

	param = SMB_MALLOC_ARRAY(char, 6+nlen+2);
	if (!param) {
		return false;
	}
	memset(param, '\0', 6);
	memset(data, 0, sizeof(data));

	SSVAL(param,0,SMB_SET_FILE_UNIX_BASIC);
	p = &param[6];

	p += clistr_push(cli, p, fname, nlen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	memset(data, 0xff, 40); /* Set all sizes/times to no change. */

	SIVAL(data,40,uid);
	SIVAL(data,48,gid);
	SIVAL(data,84,mode);

	data_len = 100;

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			(char *)&data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		SAFE_FREE(param);
		return False;
	}

	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
		return false;
	}

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return true;
}

/****************************************************************************
 chmod a file (UNIX extensions).
****************************************************************************/

bool cli_unix_chmod(struct cli_state *cli, const char *fname, mode_t mode)
{
	return cli_unix_chmod_chown_internal(cli, fname,
		unix_perms_to_wire(mode), SMB_UID_NO_CHANGE, SMB_GID_NO_CHANGE);
}

/****************************************************************************
 chown a file (UNIX extensions).
****************************************************************************/

bool cli_unix_chown(struct cli_state *cli, const char *fname, uid_t uid, gid_t gid)
{
	return cli_unix_chmod_chown_internal(cli, fname,
			SMB_MODE_NO_CHANGE, (uint32)uid, (uint32)gid);
}

/****************************************************************************
 Rename a file.
****************************************************************************/

bool cli_rename(struct cli_state *cli, const char *fname_src, const char *fname_dst)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,1, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBmv);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,aSYSTEM | aHIDDEN | aDIR);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname_src,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);
	*p++ = 4;
	p += clistr_push(cli, p, fname_dst,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return false;
	}

	if (cli_is_error(cli)) {
		return false;
	}

	return true;
}

/****************************************************************************
 NT Rename a file.
****************************************************************************/

bool cli_ntrename(struct cli_state *cli, const char *fname_src, const char *fname_dst)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf, 4, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBntrename);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,aSYSTEM | aHIDDEN | aDIR);
	SSVAL(cli->outbuf,smb_vwv1, RENAME_FLAG_RENAME);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname_src,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);
	*p++ = 4;
	p += clistr_push(cli, p, fname_dst,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return false;
	}

	if (cli_is_error(cli)) {
		return false;
	}

	return true;
}

/****************************************************************************
 NT hardlink a file.
****************************************************************************/

bool cli_nt_hardlink(struct cli_state *cli, const char *fname_src, const char *fname_dst)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf, 4, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBntrename);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,aSYSTEM | aHIDDEN | aDIR);
	SSVAL(cli->outbuf,smb_vwv1, RENAME_FLAG_HARD_LINK);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname_src,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);
	*p++ = 4;
	p += clistr_push(cli, p, fname_dst,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return false;
	}

	if (cli_is_error(cli)) {
		return false;
	}

	return true;
}

/****************************************************************************
 Delete a file.
****************************************************************************/

bool cli_unlink_full(struct cli_state *cli, const char *fname, uint16 attrs)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,1, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBunlink);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0, attrs);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);
	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return false;
	}

	if (cli_is_error(cli)) {
		return false;
	}

	return true;
}

/****************************************************************************
 Delete a file.
****************************************************************************/

bool cli_unlink(struct cli_state *cli, const char *fname)
{
	return cli_unlink_full(cli, fname, aSYSTEM | aHIDDEN);
}

/****************************************************************************
 Create a directory.
****************************************************************************/

bool cli_mkdir(struct cli_state *cli, const char *dname)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,0, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBmkdir);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, dname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Remove a directory.
****************************************************************************/

bool cli_rmdir(struct cli_state *cli, const char *dname)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,0, 0, true);

	SCVAL(cli->outbuf,smb_com,SMBrmdir);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, dname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return false;
	}

	if (cli_is_error(cli)) {
		return false;
	}

	return true;
}

/****************************************************************************
 Set or clear the delete on close flag.
****************************************************************************/

int cli_nt_delete_on_close(struct cli_state *cli, int fnum, bool flag)
{
	unsigned int data_len = 1;
	unsigned int param_len = 6;
	uint16 setup = TRANSACT2_SETFILEINFO;
	char param[6];
	unsigned char data;
	char *rparam=NULL, *rdata=NULL;

	memset(param, 0, param_len);
	SSVAL(param,0,fnum);
	SSVAL(param,2,SMB_SET_FILE_DISPOSITION_INFO);

	data = flag ? 1 : 0;

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			(char *)&data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		return false;
	}

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
		return false;
	}

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return true;
}

/****************************************************************************
 Open a file - exposing the full horror of the NT API :-).
 Used in smbtorture.
****************************************************************************/

int cli_nt_create_full(struct cli_state *cli, const char *fname,
		       uint32 CreatFlags, uint32 DesiredAccess,
		       uint32 FileAttributes, uint32 ShareAccess,
		       uint32 CreateDisposition, uint32 CreateOptions,
		       uint8 SecurityFlags)
{
	char *p;
	int len;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,24,0, true);

	SCVAL(cli->outbuf,smb_com,SMBntcreateX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,0xFF);
	if (cli->use_oplocks)
		CreatFlags |= (REQUEST_OPLOCK|REQUEST_BATCH_OPLOCK);

	SIVAL(cli->outbuf,smb_ntcreate_Flags, CreatFlags);
	SIVAL(cli->outbuf,smb_ntcreate_RootDirectoryFid, 0x0);
	SIVAL(cli->outbuf,smb_ntcreate_DesiredAccess, DesiredAccess);
	SIVAL(cli->outbuf,smb_ntcreate_FileAttributes, FileAttributes);
	SIVAL(cli->outbuf,smb_ntcreate_ShareAccess, ShareAccess);
	SIVAL(cli->outbuf,smb_ntcreate_CreateDisposition, CreateDisposition);
	SIVAL(cli->outbuf,smb_ntcreate_CreateOptions, CreateOptions);
	SIVAL(cli->outbuf,smb_ntcreate_ImpersonationLevel, 0x02);
	SCVAL(cli->outbuf,smb_ntcreate_SecurityFlags, SecurityFlags);

	p = smb_buf(cli->outbuf);
	/* this alignment and termination is critical for netapp filers. Don't change */
	p += clistr_align_out(cli, p, 0);
	len = clistr_push(cli, p, fname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), 0);
	p += len;
	SSVAL(cli->outbuf,smb_ntcreate_NameLength, len);
	/* sigh. this copes with broken netapp filer behaviour */
	p += clistr_push(cli, p, "",
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return -1;
	}

	if (cli_is_error(cli)) {
		return -1;
	}

	return SVAL(cli->inbuf,smb_vwv2 + 1);
}

struct async_req *cli_ntcreate_send(TALLOC_CTX *mem_ctx,
				    struct event_context *ev,
				    struct cli_state *cli,
				    const char *fname,
				    uint32_t CreatFlags,
				    uint32_t DesiredAccess,
				    uint32_t FileAttributes,
				    uint32_t ShareAccess,
				    uint32_t CreateDisposition,
				    uint32_t CreateOptions,
				    uint8_t SecurityFlags)
{
	struct async_req *result;
	uint8_t *bytes;
	size_t converted_len;
	uint16_t vwv[24];

	SCVAL(vwv+0, 0, 0xFF);
	SCVAL(vwv+0, 1, 0);
	SSVAL(vwv+1, 0, 0);
	SCVAL(vwv+2, 0, 0);

	if (cli->use_oplocks) {
		CreatFlags |= (REQUEST_OPLOCK|REQUEST_BATCH_OPLOCK);
	}
	SIVAL(vwv+3, 1, CreatFlags);
	SIVAL(vwv+5, 1, 0x0);	/* RootDirectoryFid */
	SIVAL(vwv+7, 1, DesiredAccess);
	SIVAL(vwv+9, 1, 0x0);	/* AllocationSize */
	SIVAL(vwv+11, 1, 0x0);	/* AllocationSize */
	SIVAL(vwv+13, 1, FileAttributes);
	SIVAL(vwv+15, 1, ShareAccess);
	SIVAL(vwv+17, 1, CreateDisposition);
	SIVAL(vwv+19, 1, CreateOptions);
	SIVAL(vwv+21, 1, 0x02);	/* ImpersonationLevel */
	SCVAL(vwv+23, 1, SecurityFlags);

	bytes = talloc_array(talloc_tos(), uint8_t, 0);
	bytes = smb_bytes_push_str(bytes, cli_ucs2(cli),
				   fname, strlen(fname)+1,
				   &converted_len);

	/* sigh. this copes with broken netapp filer behaviour */
	bytes = smb_bytes_push_str(bytes, cli_ucs2(cli), "", 1, NULL);

	if (bytes == NULL) {
		return NULL;
	}

	SIVAL(vwv+2, 1, converted_len);

	result = cli_request_send(mem_ctx, ev, cli, SMBntcreateX, 0,
				  24, vwv, 0, talloc_get_size(bytes), bytes);
	TALLOC_FREE(bytes);
	return result;
}

NTSTATUS cli_ntcreate_recv(struct async_req *req, uint16_t *pfnum)
{
	uint8_t wct;
	uint16_t *vwv;
	uint16_t num_bytes;
	uint8_t *bytes;
	NTSTATUS status;

	if (async_req_is_nterror(req, &status)) {
		return status;
	}

	status = cli_pull_reply(req, &wct, &vwv, &num_bytes, &bytes);
	if (!NT_STATUS_IS_OK(status)) {
		return status;
	}

	if (wct < 3) {
		return NT_STATUS_INVALID_NETWORK_RESPONSE;
	}

	*pfnum = SVAL(vwv+2, 1);

	return NT_STATUS_OK;
}

NTSTATUS cli_ntcreate(struct cli_state *cli,
		      const char *fname,
		      uint32_t CreatFlags,
		      uint32_t DesiredAccess,
		      uint32_t FileAttributes,
		      uint32_t ShareAccess,
		      uint32_t CreateDisposition,
		      uint32_t CreateOptions,
		      uint8_t SecurityFlags,
		      uint16_t *pfid)
{
	TALLOC_CTX *frame = talloc_stackframe();
	struct event_context *ev;
	struct async_req *req;
	NTSTATUS status;

	if (cli->fd_event != NULL) {
		/*
		 * Can't use sync call while an async call is in flight
		 */
		status = NT_STATUS_INVALID_PARAMETER;
		goto fail;
	}

	ev = event_context_init(frame);
	if (ev == NULL) {
		status = NT_STATUS_NO_MEMORY;
		goto fail;
	}

	req = cli_ntcreate_send(frame, ev, cli, fname, CreatFlags,
				DesiredAccess, FileAttributes, ShareAccess,
				CreateDisposition, CreateOptions,
				SecurityFlags);
	if (req == NULL) {
		status = NT_STATUS_NO_MEMORY;
		goto fail;
	}

	while (req->state < ASYNC_REQ_DONE) {
		event_loop_once(ev);
	}

	status = cli_ntcreate_recv(req, pfid);
 fail:
	TALLOC_FREE(frame);
	return status;
}

/****************************************************************************
 Open a file.
****************************************************************************/

int cli_nt_create(struct cli_state *cli, const char *fname, uint32 DesiredAccess)
{
	return cli_nt_create_full(cli, fname, 0, DesiredAccess, 0,
				FILE_SHARE_READ|FILE_SHARE_WRITE, FILE_OPEN, 0x0, 0x0);
}

uint8_t *smb_bytes_push_str(uint8_t *buf, bool ucs2,
			    const char *str, size_t str_len,
			    size_t *pconverted_size)
{
	size_t buflen;
	char *converted;
	size_t converted_size;

	if (buf == NULL) {
		return NULL;
	}

	buflen = talloc_get_size(buf);
	/*
	 * We're pushing into an SMB buffer, align odd
	 */
	if (ucs2 && (buflen % 2 == 0)) {
		buf = TALLOC_REALLOC_ARRAY(NULL, buf, uint8_t, buflen + 1);
		if (buf == NULL) {
			return NULL;
		}
		buf[buflen] = '\0';
		buflen += 1;
	}

	if (!convert_string_allocate(talloc_tos(), CH_UNIX,
				     ucs2 ? CH_UTF16LE : CH_DOS,
				     str, str_len, &converted,
				     &converted_size, true)) {
		return NULL;
	}

	buf = TALLOC_REALLOC_ARRAY(NULL, buf, uint8_t,
				   buflen + converted_size);
	if (buf == NULL) {
		TALLOC_FREE(converted);
		return NULL;
	}

	memcpy(buf + buflen, converted, converted_size);

	TALLOC_FREE(converted);

	if (pconverted_size) {
		*pconverted_size = converted_size;
	}

	return buf;
}

/****************************************************************************
 Open a file
 WARNING: if you open with O_WRONLY then getattrE won't work!
****************************************************************************/

struct async_req *cli_open_send(TALLOC_CTX *mem_ctx, struct event_context *ev,
				struct cli_state *cli,
				const char *fname, int flags, int share_mode)
{
	unsigned openfn = 0;
	unsigned accessmode = 0;
	uint8_t additional_flags = 0;
	uint8_t *bytes;
	uint16_t vwv[15];
	struct async_req *result;

	if (flags & O_CREAT) {
		openfn |= (1<<4);
	}
	if (!(flags & O_EXCL)) {
		if (flags & O_TRUNC)
			openfn |= (1<<1);
		else
			openfn |= (1<<0);
	}

	accessmode = (share_mode<<4);

	if ((flags & O_ACCMODE) == O_RDWR) {
		accessmode |= 2;
	} else if ((flags & O_ACCMODE) == O_WRONLY) {
		accessmode |= 1;
	}

#if defined(O_SYNC)
	if ((flags & O_SYNC) == O_SYNC) {
		accessmode |= (1<<14);
	}
#endif /* O_SYNC */

	if (share_mode == DENY_FCB) {
		accessmode = 0xFF;
	}

	SCVAL(vwv + 0, 0, 0xFF);
	SCVAL(vwv + 0, 1, 0);
	SSVAL(vwv + 1, 0, 0);
	SSVAL(vwv + 2, 0, 0);  /* no additional info */
	SSVAL(vwv + 3, 0, accessmode);
	SSVAL(vwv + 4, 0, aSYSTEM | aHIDDEN);
	SSVAL(vwv + 5, 0, 0);
	SIVAL(vwv + 6, 0, 0);
	SSVAL(vwv + 8, 0, openfn);
	SIVAL(vwv + 9, 0, 0);
	SIVAL(vwv + 11, 0, 0);
	SIVAL(vwv + 13, 0, 0);

	if (cli->use_oplocks) {
		/* if using oplocks then ask for a batch oplock via
                   core and extended methods */
		additional_flags =
			FLAG_REQUEST_OPLOCK|FLAG_REQUEST_BATCH_OPLOCK;
		SSVAL(vwv+2, 0, SVAL(vwv+2, 0) | 6);
	}

	bytes = talloc_array(talloc_tos(), uint8_t, 0);
	bytes = smb_bytes_push_str(bytes, cli_ucs2(cli), fname,
				   strlen(fname)+1, NULL);
	if (bytes == NULL) {
		return NULL;
	}

	result = cli_request_send(mem_ctx, ev, cli, SMBopenX, additional_flags,
				  15, vwv, 0, talloc_get_size(bytes), bytes);
	TALLOC_FREE(bytes);
	return result;
}

NTSTATUS cli_open_recv(struct async_req *req, int *fnum)
{
	uint8_t wct;
	uint16_t *vwv;
	uint16_t num_bytes;
	uint8_t *bytes;
	NTSTATUS status;

	if (async_req_is_nterror(req, &status)) {
		return status;
	}

	status = cli_pull_reply(req, &wct, &vwv, &num_bytes, &bytes);
	if (!NT_STATUS_IS_OK(status)) {
		return status;
	}

	if (wct < 3) {
		return NT_STATUS_INVALID_NETWORK_RESPONSE;
	}

	*fnum = SVAL(vwv+2, 0);

	return NT_STATUS_OK;
}

int cli_open(struct cli_state *cli, const char *fname, int flags,
	     int share_mode)
{
	TALLOC_CTX *frame = talloc_stackframe();
	struct event_context *ev;
	struct async_req *req;
	int result = -1;

	if (cli->fd_event != NULL) {
		/*
		 * Can't use sync call while an async call is in flight
		 */
		cli_set_error(cli, NT_STATUS_INVALID_PARAMETER);
		goto fail;
	}

	ev = event_context_init(frame);
	if (ev == NULL) {
		goto fail;
	}

	req = cli_open_send(frame, ev, cli, fname, flags, share_mode);
	if (req == NULL) {
		goto fail;
	}

	while (req->state < ASYNC_REQ_DONE) {
		event_loop_once(ev);
	}

	cli_open_recv(req, &result);
 fail:
	TALLOC_FREE(frame);
	return result;
}

/****************************************************************************
 Close a file.
****************************************************************************/

struct async_req *cli_close_send(TALLOC_CTX *mem_ctx, struct event_context *ev,
				 struct cli_state *cli, int fnum)
{
	uint16_t vwv[3];

	SSVAL(vwv+0, 0, fnum);
	SIVALS(vwv+1, 0, -1);

	return cli_request_send(mem_ctx, ev, cli, SMBclose, 0, 3, vwv, 0,
				0, NULL);
}

NTSTATUS cli_close_recv(struct async_req *req)
{
	uint8_t wct;
	uint16_t *vwv;
	uint16_t num_bytes;
	uint8_t *bytes;
	NTSTATUS status;

	if (async_req_is_nterror(req, &status)) {
		return status;
	}

	return cli_pull_reply(req, &wct, &vwv, &num_bytes, &bytes);
}

bool cli_close(struct cli_state *cli, int fnum)
{
	TALLOC_CTX *frame = talloc_stackframe();
	struct event_context *ev;
	struct async_req *req;
	bool result = false;

	if (cli->fd_event != NULL) {
		/*
		 * Can't use sync call while an async call is in flight
		 */
		cli_set_error(cli, NT_STATUS_INVALID_PARAMETER);
		goto fail;
	}

	ev = event_context_init(frame);
	if (ev == NULL) {
		goto fail;
	}

	req = cli_close_send(frame, ev, cli, fnum);
	if (req == NULL) {
		goto fail;
	}

	while (req->state < ASYNC_REQ_DONE) {
		event_loop_once(ev);
	}

	result = NT_STATUS_IS_OK(cli_close_recv(req));
 fail:
	TALLOC_FREE(frame);
	return result;
}

/****************************************************************************
 Truncate a file to a specified size
****************************************************************************/

bool cli_ftruncate(struct cli_state *cli, int fnum, uint64_t size)
{
	unsigned int param_len = 6;
	unsigned int data_len = 8;
	uint16 setup = TRANSACT2_SETFILEINFO;
	char param[6];
	unsigned char data[8];
	char *rparam=NULL, *rdata=NULL;
	int saved_timeout = cli->timeout;

	SSVAL(param,0,fnum);
	SSVAL(param,2,SMB_SET_FILE_END_OF_FILE_INFO);
	SSVAL(param,4,0);

        SBVAL(data, 0, size);

	if (!cli_send_trans(cli, SMBtrans2,
                            NULL,                    /* name */
                            -1, 0,                   /* fid, flags */
                            &setup, 1, 0,            /* setup, length, max */
                            param, param_len, 2,     /* param, length, max */
                            (char *)&data,  data_len,/* data, length, ... */
                            cli->max_xmit)) {        /* ... max */
		cli->timeout = saved_timeout;
		return False;
	}

	if (!cli_receive_trans(cli, SMBtrans2,
				&rparam, &param_len,
				&rdata, &data_len)) {
		cli->timeout = saved_timeout;
		SAFE_FREE(rdata);
		SAFE_FREE(rparam);
		return False;
	}

	cli->timeout = saved_timeout;

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return True;
}


/****************************************************************************
 send a lock with a specified locktype
 this is used for testing LOCKING_ANDX_CANCEL_LOCK
****************************************************************************/

NTSTATUS cli_locktype(struct cli_state *cli, int fnum,
		      uint32 offset, uint32 len,
		      int timeout, unsigned char locktype)
{
	char *p;
	int saved_timeout = cli->timeout;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0', smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBlockingX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SCVAL(cli->outbuf,smb_vwv0,0xFF);
	SSVAL(cli->outbuf,smb_vwv2,fnum);
	SCVAL(cli->outbuf,smb_vwv3,locktype);
	SIVALS(cli->outbuf, smb_vwv4, timeout);
	SSVAL(cli->outbuf,smb_vwv6,0);
	SSVAL(cli->outbuf,smb_vwv7,1);

	p = smb_buf(cli->outbuf);
	SSVAL(p, 0, cli->pid);
	SIVAL(p, 2, offset);
	SIVAL(p, 6, len);

	p += 10;

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);

	if (timeout != 0) {
		cli->timeout = (timeout == -1) ? 0x7FFFFFFF : (timeout + 2*1000);
	}

	if (!cli_receive_smb(cli)) {
		cli->timeout = saved_timeout;
		return NT_STATUS_UNSUCCESSFUL;
	}

	cli->timeout = saved_timeout;

	return cli_nt_error(cli);
}

/****************************************************************************
 Lock a file.
 note that timeout is in units of 2 milliseconds
****************************************************************************/

bool cli_lock(struct cli_state *cli, int fnum,
	      uint32 offset, uint32 len, int timeout, enum brl_type lock_type)
{
	char *p;
	int saved_timeout = cli->timeout;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0', smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBlockingX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SCVAL(cli->outbuf,smb_vwv0,0xFF);
	SSVAL(cli->outbuf,smb_vwv2,fnum);
	SCVAL(cli->outbuf,smb_vwv3,(lock_type == READ_LOCK? 1 : 0));
	SIVALS(cli->outbuf, smb_vwv4, timeout);
	SSVAL(cli->outbuf,smb_vwv6,0);
	SSVAL(cli->outbuf,smb_vwv7,1);

	p = smb_buf(cli->outbuf);
	SSVAL(p, 0, cli->pid);
	SIVAL(p, 2, offset);
	SIVAL(p, 6, len);

	p += 10;

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);

	if (timeout != 0) {
		cli->timeout = (timeout == -1) ? 0x7FFFFFFF : (timeout*2 + 5*1000);
	}

	if (!cli_receive_smb(cli)) {
		cli->timeout = saved_timeout;
		return False;
	}

	cli->timeout = saved_timeout;

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Unlock a file.
****************************************************************************/

bool cli_unlock(struct cli_state *cli, int fnum, uint32 offset, uint32 len)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBlockingX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SCVAL(cli->outbuf,smb_vwv0,0xFF);
	SSVAL(cli->outbuf,smb_vwv2,fnum);
	SCVAL(cli->outbuf,smb_vwv3,0);
	SIVALS(cli->outbuf, smb_vwv4, 0);
	SSVAL(cli->outbuf,smb_vwv6,1);
	SSVAL(cli->outbuf,smb_vwv7,0);

	p = smb_buf(cli->outbuf);
	SSVAL(p, 0, cli->pid);
	SIVAL(p, 2, offset);
	SIVAL(p, 6, len);
	p += 10;
	cli_setup_bcc(cli, p);
	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Lock a file with 64 bit offsets.
****************************************************************************/

bool cli_lock64(struct cli_state *cli, int fnum,
		uint64_t offset, uint64_t len, int timeout, enum brl_type lock_type)
{
	char *p;
        int saved_timeout = cli->timeout;
	int ltype;

	if (! (cli->capabilities & CAP_LARGE_FILES)) {
		return cli_lock(cli, fnum, offset, len, timeout, lock_type);
	}

	ltype = (lock_type == READ_LOCK? 1 : 0);
	ltype |= LOCKING_ANDX_LARGE_FILES;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0', smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBlockingX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SCVAL(cli->outbuf,smb_vwv0,0xFF);
	SSVAL(cli->outbuf,smb_vwv2,fnum);
	SCVAL(cli->outbuf,smb_vwv3,ltype);
	SIVALS(cli->outbuf, smb_vwv4, timeout);
	SSVAL(cli->outbuf,smb_vwv6,0);
	SSVAL(cli->outbuf,smb_vwv7,1);

	p = smb_buf(cli->outbuf);
	SIVAL(p, 0, cli->pid);
	SOFF_T_R(p, 4, offset);
	SOFF_T_R(p, 12, len);
	p += 20;

	cli_setup_bcc(cli, p);
	cli_send_smb(cli);

	if (timeout != 0) {
		cli->timeout = (timeout == -1) ? 0x7FFFFFFF : (timeout + 5*1000);
	}

	if (!cli_receive_smb(cli)) {
                cli->timeout = saved_timeout;
		return False;
	}

	cli->timeout = saved_timeout;

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Unlock a file with 64 bit offsets.
****************************************************************************/

bool cli_unlock64(struct cli_state *cli, int fnum, uint64_t offset, uint64_t len)
{
	char *p;

	if (! (cli->capabilities & CAP_LARGE_FILES)) {
		return cli_unlock(cli, fnum, offset, len);
	}

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBlockingX);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SCVAL(cli->outbuf,smb_vwv0,0xFF);
	SSVAL(cli->outbuf,smb_vwv2,fnum);
	SCVAL(cli->outbuf,smb_vwv3,LOCKING_ANDX_LARGE_FILES);
	SIVALS(cli->outbuf, smb_vwv4, 0);
	SSVAL(cli->outbuf,smb_vwv6,1);
	SSVAL(cli->outbuf,smb_vwv7,0);

	p = smb_buf(cli->outbuf);
	SIVAL(p, 0, cli->pid);
	SOFF_T_R(p, 4, offset);
	SOFF_T_R(p, 12, len);
	p += 20;
	cli_setup_bcc(cli, p);
	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Get/unlock a POSIX lock on a file - internal function.
****************************************************************************/

static bool cli_posix_lock_internal(struct cli_state *cli, int fnum,
		uint64_t offset, uint64_t len, bool wait_lock, enum brl_type lock_type)
{
	unsigned int param_len = 4;
	unsigned int data_len = POSIX_LOCK_DATA_SIZE;
	uint16 setup = TRANSACT2_SETFILEINFO;
	char param[4];
	unsigned char data[POSIX_LOCK_DATA_SIZE];
	char *rparam=NULL, *rdata=NULL;
	int saved_timeout = cli->timeout;

	SSVAL(param,0,fnum);
	SSVAL(param,2,SMB_SET_POSIX_LOCK);

	switch (lock_type) {
		case READ_LOCK:
			SSVAL(data, POSIX_LOCK_TYPE_OFFSET, POSIX_LOCK_TYPE_READ);
			break;
		case WRITE_LOCK:
			SSVAL(data, POSIX_LOCK_TYPE_OFFSET, POSIX_LOCK_TYPE_WRITE);
			break;
		case UNLOCK_LOCK:
			SSVAL(data, POSIX_LOCK_TYPE_OFFSET, POSIX_LOCK_TYPE_UNLOCK);
			break;
		default:
			return False;
	}

	if (wait_lock) {
		SSVAL(data, POSIX_LOCK_FLAGS_OFFSET, POSIX_LOCK_FLAG_WAIT);
		cli->timeout = 0x7FFFFFFF;
	} else {
		SSVAL(data, POSIX_LOCK_FLAGS_OFFSET, POSIX_LOCK_FLAG_NOWAIT);
	}

	SIVAL(data, POSIX_LOCK_PID_OFFSET, cli->pid);
	SOFF_T(data, POSIX_LOCK_START_OFFSET, offset);
	SOFF_T(data, POSIX_LOCK_LEN_OFFSET, len);

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			(char *)&data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		cli->timeout = saved_timeout;
		return False;
	}

	if (!cli_receive_trans(cli, SMBtrans2,
				&rparam, &param_len,
				&rdata, &data_len)) {
		cli->timeout = saved_timeout;
		SAFE_FREE(rdata);
		SAFE_FREE(rparam);
		return False;
	}

	cli->timeout = saved_timeout;

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return True;
}

/****************************************************************************
 POSIX Lock a file.
****************************************************************************/

bool cli_posix_lock(struct cli_state *cli, int fnum,
			uint64_t offset, uint64_t len,
			bool wait_lock, enum brl_type lock_type)
{
	if (lock_type != READ_LOCK && lock_type != WRITE_LOCK) {
		return False;
	}
	return cli_posix_lock_internal(cli, fnum, offset, len, wait_lock, lock_type);
}

/****************************************************************************
 POSIX Unlock a file.
****************************************************************************/

bool cli_posix_unlock(struct cli_state *cli, int fnum, uint64_t offset, uint64_t len)
{
	return cli_posix_lock_internal(cli, fnum, offset, len, False, UNLOCK_LOCK);
}

/****************************************************************************
 POSIX Get any lock covering a file.
****************************************************************************/

bool cli_posix_getlock(struct cli_state *cli, int fnum, uint64_t *poffset, uint64_t *plen)
{
	return True;
}

/****************************************************************************
 Do a SMBgetattrE call.
****************************************************************************/

bool cli_getattrE(struct cli_state *cli, int fd,
		  uint16 *attr, SMB_OFF_T *size,
		  time_t *change_time,
                  time_t *access_time,
                  time_t *write_time)
{
	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,1,0,True);

	SCVAL(cli->outbuf,smb_com,SMBgetattrE);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,fd);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	if (size) {
		*size = IVAL(cli->inbuf, smb_vwv6);
	}

	if (attr) {
		*attr = SVAL(cli->inbuf,smb_vwv10);
	}

	if (change_time) {
		*change_time = cli_make_unix_date2(cli, cli->inbuf+smb_vwv0);
	}

	if (access_time) {
		*access_time = cli_make_unix_date2(cli, cli->inbuf+smb_vwv2);
	}

	if (write_time) {
		*write_time = cli_make_unix_date2(cli, cli->inbuf+smb_vwv4);
	}

	return True;
}

/****************************************************************************
 Do a SMBgetatr call
****************************************************************************/

bool cli_getatr(struct cli_state *cli, const char *fname,
		uint16 *attr, SMB_OFF_T *size, time_t *write_time)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,0,0,True);

	SCVAL(cli->outbuf,smb_com,SMBgetatr);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	if (size) {
		*size = IVAL(cli->inbuf, smb_vwv3);
	}

	if (write_time) {
		*write_time = cli_make_unix_date3(cli, cli->inbuf+smb_vwv1);
	}

	if (attr) {
		*attr = SVAL(cli->inbuf,smb_vwv0);
	}

	return True;
}

/****************************************************************************
 Do a SMBsetattrE call.
****************************************************************************/

bool cli_setattrE(struct cli_state *cli, int fd,
		  time_t change_time,
                  time_t access_time,
                  time_t write_time)

{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,7,0,True);

	SCVAL(cli->outbuf,smb_com,SMBsetattrE);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0, fd);
	cli_put_dos_date2(cli, cli->outbuf,smb_vwv1, change_time);
	cli_put_dos_date2(cli, cli->outbuf,smb_vwv3, access_time);
	cli_put_dos_date2(cli, cli->outbuf,smb_vwv5, write_time);

	p = smb_buf(cli->outbuf);
	*p++ = 4;

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Do a SMBsetatr call.
****************************************************************************/

bool cli_setatr(struct cli_state *cli, const char *fname, uint16 attr, time_t t)
{
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,8,0,True);

	SCVAL(cli->outbuf,smb_com,SMBsetatr);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0, attr);
	cli_put_dos_date3(cli, cli->outbuf,smb_vwv1, t);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, fname,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);
	*p++ = 4;

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	if (cli_is_error(cli)) {
		return False;
	}

	return True;
}

/****************************************************************************
 Check for existance of a dir.
****************************************************************************/

bool cli_chkpath(struct cli_state *cli, const char *path)
{
	char *path2 = NULL;
	char *p;
	TALLOC_CTX *frame = talloc_stackframe();

	path2 = talloc_strdup(frame, path);
	if (!path2) {
		TALLOC_FREE(frame);
		return false;
	}
	trim_char(path2,'\0','\\');
	if (!*path2) {
		path2 = talloc_strdup(frame, "\\");
		if (!path2) {
			TALLOC_FREE(frame);
			return false;
		}
	}

	memset(cli->outbuf,'\0',smb_size);
	cli_set_message(cli->outbuf,0,0,True);
	SCVAL(cli->outbuf,smb_com,SMBcheckpath);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);
	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, path2,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		TALLOC_FREE(frame);
		return False;
	}

	TALLOC_FREE(frame);

	if (cli_is_error(cli)) return False;

	return True;
}

/****************************************************************************
 Query disk space.
****************************************************************************/

bool cli_dskattr(struct cli_state *cli, int *bsize, int *total, int *avail)
{
	memset(cli->outbuf,'\0',smb_size);
	cli_set_message(cli->outbuf,0,0,True);
	SCVAL(cli->outbuf,smb_com,SMBdskattr);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return False;
	}

	*bsize = SVAL(cli->inbuf,smb_vwv1)*SVAL(cli->inbuf,smb_vwv2);
	*total = SVAL(cli->inbuf,smb_vwv0);
	*avail = SVAL(cli->inbuf,smb_vwv3);

	return True;
}

/****************************************************************************
 Create and open a temporary file.
****************************************************************************/

int cli_ctemp(struct cli_state *cli, const char *path, char **tmp_path)
{
	int len;
	char *p;

	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf,3,0,True);

	SCVAL(cli->outbuf,smb_com,SMBctemp);
	SSVAL(cli->outbuf,smb_tid,cli->cnum);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf,smb_vwv0,0);
	SIVALS(cli->outbuf,smb_vwv1,-1);

	p = smb_buf(cli->outbuf);
	*p++ = 4;
	p += clistr_push(cli, p, path,
			cli->bufsize - PTR_DIFF(p,cli->outbuf), STR_TERMINATE);

	cli_setup_bcc(cli, p);

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return -1;
	}

	if (cli_is_error(cli)) {
		return -1;
	}

	/* despite the spec, the result has a -1, followed by
	   length, followed by name */
	p = smb_buf(cli->inbuf);
	p += 4;
	len = smb_buflen(cli->inbuf) - 4;
	if (len <= 0 || len > PATH_MAX) return -1;

	if (tmp_path) {
		char *path2 = SMB_MALLOC_ARRAY(char, len+1);
		if (!path2) {
			return -1;
		}
		clistr_pull(cli->inbuf, path2, p,
			    len+1, len, STR_ASCII);
		*tmp_path = path2;
	}

	return SVAL(cli->inbuf,smb_vwv0);
}

/*
   send a raw ioctl - used by the torture code
*/
NTSTATUS cli_raw_ioctl(struct cli_state *cli, int fnum, uint32 code, DATA_BLOB *blob)
{
	memset(cli->outbuf,'\0',smb_size);
	memset(cli->inbuf,'\0',smb_size);

	cli_set_message(cli->outbuf, 3, 0, True);
	SCVAL(cli->outbuf,smb_com,SMBioctl);
	cli_setup_packet(cli);

	SSVAL(cli->outbuf, smb_vwv0, fnum);
	SSVAL(cli->outbuf, smb_vwv1, code>>16);
	SSVAL(cli->outbuf, smb_vwv2, (code&0xFFFF));

	cli_send_smb(cli);
	if (!cli_receive_smb(cli)) {
		return NT_STATUS_UNEXPECTED_NETWORK_ERROR;
	}

	if (cli_is_error(cli)) {
		return cli_nt_error(cli);
	}

	*blob = data_blob_null;

	return NT_STATUS_OK;
}

/*********************************************************
 Set an extended attribute utility fn.
*********************************************************/

static bool cli_set_ea(struct cli_state *cli, uint16 setup, char *param, unsigned int param_len,
			const char *ea_name, const char *ea_val, size_t ea_len)
{
	unsigned int data_len = 0;
	char *data = NULL;
	char *rparam=NULL, *rdata=NULL;
	char *p;
	size_t ea_namelen = strlen(ea_name);

	if (ea_namelen == 0 && ea_len == 0) {
		data_len = 4;
		data = (char *)SMB_MALLOC(data_len);
		if (!data) {
			return False;
		}
		p = data;
		SIVAL(p,0,data_len);
	} else {
		data_len = 4 + 4 + ea_namelen + 1 + ea_len;
		data = (char *)SMB_MALLOC(data_len);
		if (!data) {
			return False;
		}
		p = data;
		SIVAL(p,0,data_len);
		p += 4;
		SCVAL(p, 0, 0); /* EA flags. */
		SCVAL(p, 1, ea_namelen);
		SSVAL(p, 2, ea_len);
		memcpy(p+4, ea_name, ea_namelen+1); /* Copy in the name. */
		memcpy(p+4+ea_namelen+1, ea_val, ea_len);
	}

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		SAFE_FREE(data);
		return False;
	}

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &param_len,
			&rdata, &data_len)) {
			SAFE_FREE(data);
		return false;
	}

	SAFE_FREE(data);
	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return True;
}

/*********************************************************
 Set an extended attribute on a pathname.
*********************************************************/

bool cli_set_ea_path(struct cli_state *cli, const char *path, const char *ea_name, const char *ea_val, size_t ea_len)
{
	uint16 setup = TRANSACT2_SETPATHINFO;
	unsigned int param_len = 0;
	char *param;
	size_t srclen = 2*(strlen(path)+1);
	char *p;
	bool ret;

	param = SMB_MALLOC_ARRAY(char, 6+srclen+2);
	if (!param) {
		return false;
	}
	memset(param, '\0', 6);
	SSVAL(param,0,SMB_INFO_SET_EA);
	p = &param[6];

	p += clistr_push(cli, p, path, srclen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	ret = cli_set_ea(cli, setup, param, param_len, ea_name, ea_val, ea_len);
	SAFE_FREE(param);
	return ret;
}

/*********************************************************
 Set an extended attribute on an fnum.
*********************************************************/

bool cli_set_ea_fnum(struct cli_state *cli, int fnum, const char *ea_name, const char *ea_val, size_t ea_len)
{
	char param[6];
	uint16 setup = TRANSACT2_SETFILEINFO;

	memset(param, 0, 6);
	SSVAL(param,0,fnum);
	SSVAL(param,2,SMB_INFO_SET_EA);

	return cli_set_ea(cli, setup, param, 6, ea_name, ea_val, ea_len);
}

/*********************************************************
 Get an extended attribute list utility fn.
*********************************************************/

static bool cli_get_ea_list(struct cli_state *cli,
		uint16 setup, char *param, unsigned int param_len,
		TALLOC_CTX *ctx,
		size_t *pnum_eas,
		struct ea_struct **pea_list)
{
	unsigned int data_len = 0;
	unsigned int rparam_len, rdata_len;
	char *rparam=NULL, *rdata=NULL;
	char *p;
	size_t ea_size;
	size_t num_eas;
	bool ret = False;
	struct ea_struct *ea_list;

	*pnum_eas = 0;
	if (pea_list) {
	 	*pea_list = NULL;
	}

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,           /* Name */
			-1, 0,          /* fid, flags */
			&setup, 1, 0,   /* setup, length, max */
			param, param_len, 10, /* param, length, max */
			NULL, data_len, cli->max_xmit /* data, length, max */
				)) {
		return False;
	}

	if (!cli_receive_trans(cli, SMBtrans2,
			&rparam, &rparam_len,
			&rdata, &rdata_len)) {
		return False;
	}

	if (!rdata || rdata_len < 4) {
		goto out;
	}

	ea_size = (size_t)IVAL(rdata,0);
	if (ea_size > rdata_len) {
		goto out;
	}

	if (ea_size == 0) {
		/* No EA's present. */
		ret = True;
		goto out;
	}

	p = rdata + 4;
	ea_size -= 4;

	/* Validate the EA list and count it. */
	for (num_eas = 0; ea_size >= 4; num_eas++) {
		unsigned int ea_namelen = CVAL(p,1);
		unsigned int ea_valuelen = SVAL(p,2);
		if (ea_namelen == 0) {
			goto out;
		}
		if (4 + ea_namelen + 1 + ea_valuelen > ea_size) {
			goto out;
		}
		ea_size -= 4 + ea_namelen + 1 + ea_valuelen;
		p += 4 + ea_namelen + 1 + ea_valuelen;
	}

	if (num_eas == 0) {
		ret = True;
		goto out;
	}

	*pnum_eas = num_eas;
	if (!pea_list) {
		/* Caller only wants number of EA's. */
		ret = True;
		goto out;
	}

	ea_list = TALLOC_ARRAY(ctx, struct ea_struct, num_eas);
	if (!ea_list) {
		goto out;
	}

	ea_size = (size_t)IVAL(rdata,0);
	p = rdata + 4;

	for (num_eas = 0; num_eas < *pnum_eas; num_eas++ ) {
		struct ea_struct *ea = &ea_list[num_eas];
		fstring unix_ea_name;
		unsigned int ea_namelen = CVAL(p,1);
		unsigned int ea_valuelen = SVAL(p,2);

		ea->flags = CVAL(p,0);
		unix_ea_name[0] = '\0';
		pull_ascii_fstring(unix_ea_name, p + 4);
		ea->name = talloc_strdup(ctx, unix_ea_name);
		/* Ensure the value is null terminated (in case it's a string). */
		ea->value = data_blob_talloc(ctx, NULL, ea_valuelen + 1);
		if (!ea->value.data) {
			goto out;
		}
		if (ea_valuelen) {
			memcpy(ea->value.data, p+4+ea_namelen+1, ea_valuelen);
		}
		ea->value.data[ea_valuelen] = 0;
		ea->value.length--;
		p += 4 + ea_namelen + 1 + ea_valuelen;
	}

	*pea_list = ea_list;
	ret = True;

 out :

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);
	return ret;
}

/*********************************************************
 Get an extended attribute list from a pathname.
*********************************************************/

bool cli_get_ea_list_path(struct cli_state *cli, const char *path,
		TALLOC_CTX *ctx,
		size_t *pnum_eas,
		struct ea_struct **pea_list)
{
	uint16 setup = TRANSACT2_QPATHINFO;
	unsigned int param_len = 0;
	char *param;
	char *p;
	size_t srclen = 2*(strlen(path)+1);
	bool ret;

	param = SMB_MALLOC_ARRAY(char, 6+srclen+2);
	if (!param) {
		return false;
	}
	p = param;
	memset(p, 0, 6);
	SSVAL(p, 0, SMB_INFO_QUERY_ALL_EAS);
	p += 6;
	p += clistr_push(cli, p, path, srclen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	ret = cli_get_ea_list(cli, setup, param, param_len, ctx, pnum_eas, pea_list);
	SAFE_FREE(param);
	return ret;
}

/*********************************************************
 Get an extended attribute list from an fnum.
*********************************************************/

bool cli_get_ea_list_fnum(struct cli_state *cli, int fnum,
		TALLOC_CTX *ctx,
		size_t *pnum_eas,
		struct ea_struct **pea_list)
{
	uint16 setup = TRANSACT2_QFILEINFO;
	char param[6];

	memset(param, 0, 6);
	SSVAL(param,0,fnum);
	SSVAL(param,2,SMB_INFO_SET_EA);

	return cli_get_ea_list(cli, setup, param, 6, ctx, pnum_eas, pea_list);
}

/****************************************************************************
 Convert open "flags" arg to uint32 on wire.
****************************************************************************/

static uint32 open_flags_to_wire(int flags)
{
	int open_mode = flags & O_ACCMODE;
	uint32 ret = 0;

	switch (open_mode) {
		case O_WRONLY:
			ret |= SMB_O_WRONLY;
			break;
		case O_RDWR:
			ret |= SMB_O_RDWR;
			break;
		default:
		case O_RDONLY:
			ret |= SMB_O_RDONLY;
			break;
	}

	if (flags & O_CREAT) {
		ret |= SMB_O_CREAT;
	}
	if (flags & O_EXCL) {
		ret |= SMB_O_EXCL;
	}
	if (flags & O_TRUNC) {
		ret |= SMB_O_TRUNC;
	}
#if defined(O_SYNC)
	if (flags & O_SYNC) {
		ret |= SMB_O_SYNC;
	}
#endif /* O_SYNC */
	if (flags & O_APPEND) {
		ret |= SMB_O_APPEND;
	}
#if defined(O_DIRECT)
	if (flags & O_DIRECT) {
		ret |= SMB_O_DIRECT;
	}
#endif
#if defined(O_DIRECTORY)
	if (flags & O_DIRECTORY) {
		ret &= ~(SMB_O_RDONLY|SMB_O_RDWR|SMB_O_WRONLY);
		ret |= SMB_O_DIRECTORY;
	}
#endif
	return ret;
}

/****************************************************************************
 Open a file - POSIX semantics. Returns fnum. Doesn't request oplock.
****************************************************************************/

static int cli_posix_open_internal(struct cli_state *cli, const char *fname, int flags, mode_t mode, bool is_dir)
{
	unsigned int data_len = 0;
	unsigned int param_len = 0;
	uint16 setup = TRANSACT2_SETPATHINFO;
	char *param;
	char data[18];
	char *rparam=NULL, *rdata=NULL;
	char *p;
	int fnum = -1;
	uint32 wire_flags = open_flags_to_wire(flags);
	size_t srclen = 2*(strlen(fname)+1);

	param = SMB_MALLOC_ARRAY(char, 6+srclen+2);
	if (!param) {
		return false;
	}
	memset(param, '\0', 6);
	SSVAL(param,0, SMB_POSIX_PATH_OPEN);
	p = &param[6];

	p += clistr_push(cli, p, fname, srclen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	if (is_dir) {
		wire_flags &= ~(SMB_O_RDONLY|SMB_O_RDWR|SMB_O_WRONLY);
		wire_flags |= SMB_O_DIRECTORY;
	}

	p = data;
	SIVAL(p,0,0); /* No oplock. */
	SIVAL(p,4,wire_flags);
	SIVAL(p,8,unix_perms_to_wire(mode));
	SIVAL(p,12,0); /* Top bits of perms currently undefined. */
	SSVAL(p,16,SMB_NO_INFO_LEVEL_RETURNED); /* No info level returned. */

	data_len = 18;

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			(char *)&data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		SAFE_FREE(param);
		return -1;
	}

	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
		&rparam, &param_len,
		&rdata, &data_len)) {
			return -1;
	}

	fnum = SVAL(rdata,2);

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return fnum;
}

/****************************************************************************
 open - POSIX semantics.
****************************************************************************/

int cli_posix_open(struct cli_state *cli, const char *fname, int flags, mode_t mode)
{
	return cli_posix_open_internal(cli, fname, flags, mode, False);
}

/****************************************************************************
 mkdir - POSIX semantics.
****************************************************************************/

int cli_posix_mkdir(struct cli_state *cli, const char *fname, mode_t mode)
{
	return (cli_posix_open_internal(cli, fname, O_CREAT, mode, True) == -1) ? -1 : 0;
}

/****************************************************************************
 unlink or rmdir - POSIX semantics.
****************************************************************************/

static bool cli_posix_unlink_internal(struct cli_state *cli, const char *fname, bool is_dir)
{
	unsigned int data_len = 0;
	unsigned int param_len = 0;
	uint16 setup = TRANSACT2_SETPATHINFO;
	char *param;
	char data[2];
	char *rparam=NULL, *rdata=NULL;
	char *p;
	size_t srclen = 2*(strlen(fname)+1);

	param = SMB_MALLOC_ARRAY(char, 6+srclen+2);
	if (!param) {
		return false;
	}
	memset(param, '\0', 6);
	SSVAL(param,0, SMB_POSIX_PATH_UNLINK);
	p = &param[6];

	p += clistr_push(cli, p, fname, srclen, STR_TERMINATE);
	param_len = PTR_DIFF(p, param);

	SSVAL(data, 0, is_dir ? SMB_POSIX_UNLINK_DIRECTORY_TARGET :
			SMB_POSIX_UNLINK_FILE_TARGET);
	data_len = 2;

	if (!cli_send_trans(cli, SMBtrans2,
			NULL,                        /* name */
			-1, 0,                          /* fid, flags */
			&setup, 1, 0,                   /* setup, length, max */
			param, param_len, 2,            /* param, length, max */
			(char *)&data,  data_len, cli->max_xmit /* data, length, max */
			)) {
		SAFE_FREE(param);
		return False;
	}

	SAFE_FREE(param);

	if (!cli_receive_trans(cli, SMBtrans2,
		&rparam, &param_len,
		&rdata, &data_len)) {
			return False;
	}

	SAFE_FREE(rdata);
	SAFE_FREE(rparam);

	return True;
}

/****************************************************************************
 unlink - POSIX semantics.
****************************************************************************/

bool cli_posix_unlink(struct cli_state *cli, const char *fname)
{
	return cli_posix_unlink_internal(cli, fname, False);
}

/****************************************************************************
 rmdir - POSIX semantics.
****************************************************************************/

int cli_posix_rmdir(struct cli_state *cli, const char *fname)
{
	return cli_posix_unlink_internal(cli, fname, True);
}
