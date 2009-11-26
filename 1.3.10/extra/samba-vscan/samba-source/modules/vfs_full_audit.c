/* 
 * Auditing VFS module for samba.  Log selected file operations to syslog
 * facility.
 *
 * Copyright (C) Tim Potter, 1999-2000
 * Copyright (C) Alexander Bokovoy, 2002
 * Copyright (C) John H Terpstra, 2003
 * Copyright (C) Stefan (metze) Metzmacher, 2003
 * Copyright (C) Volker Lendecke, 2004
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *  
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *  
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

/*
 * This module implements parseable logging for all Samba VFS operations.
 *
 * You use it as follows:
 *
 * [tmp]
 * path = /tmp
 * vfs objects = full_audit
 * full_audit:prefix = %u|%I
 * full_audit:success = open opendir
 * full_audit:failure = all
 *
 * vfs op can be "all" which means log all operations.
 * vfs op can be "none" which means no logging.
 *
 * This leads to syslog entries of the form:
 * smbd_audit: nobody|192.168.234.1|opendir|ok|.
 * smbd_audit: nobody|192.168.234.1|open|fail (File not found)|r|x.txt
 *
 * where "nobody" is the connected username and "192.168.234.1" is the
 * client's IP address. 
 *
 * Options:
 *
 * prefix: A macro expansion template prepended to the syslog entry.
 *
 * success: A list of VFS operations for which a successful completion should
 * be logged. Defaults to no logging at all. The special operation "all" logs
 * - you guessed it - everything.
 *
 * failure: A list of VFS operations for which failure to complete should be
 * logged. Defaults to logging everything.
 */


#include "includes.h"

static int vfs_full_audit_debug_level = DBGC_VFS;

struct vfs_full_audit_private_data {
	struct bitmap *success_ops;
	struct bitmap *failure_ops;
};

#undef DBGC_CLASS
#define DBGC_CLASS vfs_full_audit_debug_level

/* Function prototypes */

static int smb_full_audit_connect(vfs_handle_struct *handle,
			 const char *svc, const char *user);
static void smb_full_audit_disconnect(vfs_handle_struct *handle);
static uint64_t smb_full_audit_disk_free(vfs_handle_struct *handle,
				    const char *path,
				    bool small_query, uint64_t *bsize, 
				    uint64_t *dfree, uint64_t *dsize);
static int smb_full_audit_get_quota(struct vfs_handle_struct *handle,
			   enum SMB_QUOTA_TYPE qtype, unid_t id,
			   SMB_DISK_QUOTA *qt);
static int smb_full_audit_set_quota(struct vfs_handle_struct *handle,
			   enum SMB_QUOTA_TYPE qtype, unid_t id,
			   SMB_DISK_QUOTA *qt);
static int smb_full_audit_get_shadow_copy_data(struct vfs_handle_struct *handle,
                                struct files_struct *fsp,
                                SHADOW_COPY_DATA *shadow_copy_data, bool labels);
static int smb_full_audit_statvfs(struct vfs_handle_struct *handle,
				const char *path,
				struct vfs_statvfs_struct *statbuf);
static int smb_full_audit_fs_capabilities(struct vfs_handle_struct *handle);
static SMB_STRUCT_DIR *smb_full_audit_opendir(vfs_handle_struct *handle,
			  const char *fname, const char *mask, uint32 attr);
static SMB_STRUCT_DIRENT *smb_full_audit_readdir(vfs_handle_struct *handle,
				    SMB_STRUCT_DIR *dirp,
				    SMB_STRUCT_STAT *sbuf);
static void smb_full_audit_seekdir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp, long offset);
static long smb_full_audit_telldir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp);
static void smb_full_audit_rewinddir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp);
static int smb_full_audit_mkdir(vfs_handle_struct *handle,
		       const char *path, mode_t mode);
static int smb_full_audit_rmdir(vfs_handle_struct *handle,
		       const char *path);
static int smb_full_audit_closedir(vfs_handle_struct *handle,
			  SMB_STRUCT_DIR *dirp);
static void smb_full_audit_init_search_op(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp);
static int smb_full_audit_open(vfs_handle_struct *handle,
		      const char *fname, files_struct *fsp, int flags, mode_t mode);
static NTSTATUS smb_full_audit_create_file(vfs_handle_struct *handle,
				      struct smb_request *req,
				      uint16_t root_dir_fid,
				      const char *fname,
				      uint32_t create_file_flags,
				      uint32_t access_mask,
				      uint32_t share_access,
				      uint32_t create_disposition,
				      uint32_t create_options,
				      uint32_t file_attributes,
				      uint32_t oplock_request,
				      uint64_t allocation_size,
				      struct security_descriptor *sd,
				      struct ea_list *ea_list,
				      files_struct **result,
				      int *pinfo,
				      SMB_STRUCT_STAT *psbuf);
static int smb_full_audit_close(vfs_handle_struct *handle, files_struct *fsp);
static ssize_t smb_full_audit_read(vfs_handle_struct *handle, files_struct *fsp,
			  void *data, size_t n);
static ssize_t smb_full_audit_pread(vfs_handle_struct *handle, files_struct *fsp,
			   void *data, size_t n, SMB_OFF_T offset);
static ssize_t smb_full_audit_write(vfs_handle_struct *handle, files_struct *fsp,
			   const void *data, size_t n);
static ssize_t smb_full_audit_pwrite(vfs_handle_struct *handle, files_struct *fsp,
			    const void *data, size_t n,
			    SMB_OFF_T offset);
static SMB_OFF_T smb_full_audit_lseek(vfs_handle_struct *handle, files_struct *fsp,
			     SMB_OFF_T offset, int whence);
static ssize_t smb_full_audit_sendfile(vfs_handle_struct *handle, int tofd,
			      files_struct *fromfsp,
			      const DATA_BLOB *hdr, SMB_OFF_T offset,
			      size_t n);
static ssize_t smb_full_audit_recvfile(vfs_handle_struct *handle, int fromfd,
			      files_struct *tofsp,
			      SMB_OFF_T offset,
			      size_t n);
static int smb_full_audit_rename(vfs_handle_struct *handle,
			const char *oldname, const char *newname);
static int smb_full_audit_fsync(vfs_handle_struct *handle, files_struct *fsp);
static int smb_full_audit_stat(vfs_handle_struct *handle,
		      const char *fname, SMB_STRUCT_STAT *sbuf);
static int smb_full_audit_fstat(vfs_handle_struct *handle, files_struct *fsp,
		       SMB_STRUCT_STAT *sbuf);
static int smb_full_audit_lstat(vfs_handle_struct *handle,
		       const char *path, SMB_STRUCT_STAT *sbuf);
static int smb_full_audit_get_alloc_size(vfs_handle_struct *handle,
		       files_struct *fsp, const SMB_STRUCT_STAT *sbuf);
static int smb_full_audit_unlink(vfs_handle_struct *handle,
			const char *path);
static int smb_full_audit_chmod(vfs_handle_struct *handle,
		       const char *path, mode_t mode);
static int smb_full_audit_fchmod(vfs_handle_struct *handle, files_struct *fsp,
			mode_t mode);
static int smb_full_audit_chown(vfs_handle_struct *handle,
		       const char *path, uid_t uid, gid_t gid);
static int smb_full_audit_fchown(vfs_handle_struct *handle, files_struct *fsp,
			uid_t uid, gid_t gid);
static int smb_full_audit_lchown(vfs_handle_struct *handle,
		       const char *path, uid_t uid, gid_t gid);
static int smb_full_audit_chdir(vfs_handle_struct *handle,
		       const char *path);
static char *smb_full_audit_getwd(vfs_handle_struct *handle,
			 char *path);
static int smb_full_audit_ntimes(vfs_handle_struct *handle,
		       const char *path, struct smb_file_time *ft);
static int smb_full_audit_ftruncate(vfs_handle_struct *handle, files_struct *fsp,
			   SMB_OFF_T len);
static bool smb_full_audit_lock(vfs_handle_struct *handle, files_struct *fsp,
		       int op, SMB_OFF_T offset, SMB_OFF_T count, int type);
static int smb_full_audit_kernel_flock(struct vfs_handle_struct *handle,
				       struct files_struct *fsp,
				       uint32 share_mode);
static int smb_full_audit_linux_setlease(vfs_handle_struct *handle, files_struct *fsp,
					int leasetype);
static bool smb_full_audit_getlock(vfs_handle_struct *handle, files_struct *fsp,
		       SMB_OFF_T *poffset, SMB_OFF_T *pcount, int *ptype, pid_t *ppid);
static int smb_full_audit_symlink(vfs_handle_struct *handle,
			 const char *oldpath, const char *newpath);
static int smb_full_audit_readlink(vfs_handle_struct *handle,
			  const char *path, char *buf, size_t bufsiz);
static int smb_full_audit_link(vfs_handle_struct *handle,
		      const char *oldpath, const char *newpath);
static int smb_full_audit_mknod(vfs_handle_struct *handle,
		       const char *pathname, mode_t mode, SMB_DEV_T dev);
static char *smb_full_audit_realpath(vfs_handle_struct *handle,
			    const char *path, char *resolved_path);
static NTSTATUS smb_full_audit_notify_watch(struct vfs_handle_struct *handle,
			struct sys_notify_context *ctx,
			struct notify_entry *e,
			void (*callback)(struct sys_notify_context *ctx,
					void *private_data,
					struct notify_event *ev),
			void *private_data, void *handle_p);
static int smb_full_audit_chflags(vfs_handle_struct *handle,
			    const char *path, unsigned int flags);
static struct file_id smb_full_audit_file_id_create(struct vfs_handle_struct *handle,
						    const SMB_STRUCT_STAT *sbuf);
static NTSTATUS smb_full_audit_streaminfo(vfs_handle_struct *handle,
					  struct files_struct *fsp,
					  const char *fname,
					  TALLOC_CTX *mem_ctx,
					  unsigned int *pnum_streams,
					  struct stream_struct **pstreams);
static int smb_full_audit_get_real_filename(struct vfs_handle_struct *handle,
					    const char *path,
					    const char *name,
					    TALLOC_CTX *mem_ctx,
					    char **found_name);
static NTSTATUS smb_full_audit_brl_lock_windows(struct vfs_handle_struct *handle,
					        struct byte_range_lock *br_lck,
					        struct lock_struct *plock,
					        bool blocking_lock,
						struct blocking_lock_record *blr);
static bool smb_full_audit_brl_unlock_windows(struct vfs_handle_struct *handle,
					      struct messaging_context *msg_ctx,
				              struct byte_range_lock *br_lck,
				              const struct lock_struct *plock);
static bool smb_full_audit_brl_cancel_windows(struct vfs_handle_struct *handle,
				              struct byte_range_lock *br_lck,
					      struct lock_struct *plock,
					      struct blocking_lock_record *blr);
static bool smb_full_audit_strict_lock(struct vfs_handle_struct *handle,
				       struct files_struct *fsp,
				       struct lock_struct *plock);
static void smb_full_audit_strict_unlock(struct vfs_handle_struct *handle,
				         struct files_struct *fsp,
				         struct lock_struct *plock);
static NTSTATUS smb_full_audit_fget_nt_acl(vfs_handle_struct *handle, files_struct *fsp,
				uint32 security_info,
				SEC_DESC **ppdesc);
static NTSTATUS smb_full_audit_get_nt_acl(vfs_handle_struct *handle,
			       const char *name, uint32 security_info,
			       SEC_DESC **ppdesc);
static NTSTATUS smb_full_audit_fset_nt_acl(vfs_handle_struct *handle, files_struct *fsp,
			      uint32 security_info_sent,
			      const SEC_DESC *psd);
static int smb_full_audit_chmod_acl(vfs_handle_struct *handle,
			   const char *path, mode_t mode);
static int smb_full_audit_fchmod_acl(vfs_handle_struct *handle, files_struct *fsp,
				     mode_t mode);
static int smb_full_audit_sys_acl_get_entry(vfs_handle_struct *handle,
				   SMB_ACL_T theacl, int entry_id,
				   SMB_ACL_ENTRY_T *entry_p);
static int smb_full_audit_sys_acl_get_tag_type(vfs_handle_struct *handle,
				      SMB_ACL_ENTRY_T entry_d,
				      SMB_ACL_TAG_T *tag_type_p);
static int smb_full_audit_sys_acl_get_permset(vfs_handle_struct *handle,
				     SMB_ACL_ENTRY_T entry_d,
				     SMB_ACL_PERMSET_T *permset_p);
static void * smb_full_audit_sys_acl_get_qualifier(vfs_handle_struct *handle,
					  SMB_ACL_ENTRY_T entry_d);
static SMB_ACL_T smb_full_audit_sys_acl_get_file(vfs_handle_struct *handle,
					const char *path_p,
					SMB_ACL_TYPE_T type);
static SMB_ACL_T smb_full_audit_sys_acl_get_fd(vfs_handle_struct *handle,
				      files_struct *fsp);
static int smb_full_audit_sys_acl_clear_perms(vfs_handle_struct *handle,
				     SMB_ACL_PERMSET_T permset);
static int smb_full_audit_sys_acl_add_perm(vfs_handle_struct *handle,
				  SMB_ACL_PERMSET_T permset,
				  SMB_ACL_PERM_T perm);
static char * smb_full_audit_sys_acl_to_text(vfs_handle_struct *handle,
				    SMB_ACL_T theacl,
				    ssize_t *plen);
static SMB_ACL_T smb_full_audit_sys_acl_init(vfs_handle_struct *handle,
				    int count);
static int smb_full_audit_sys_acl_create_entry(vfs_handle_struct *handle,
				      SMB_ACL_T *pacl,
				      SMB_ACL_ENTRY_T *pentry);
static int smb_full_audit_sys_acl_set_tag_type(vfs_handle_struct *handle,
				      SMB_ACL_ENTRY_T entry,
				      SMB_ACL_TAG_T tagtype);
static int smb_full_audit_sys_acl_set_qualifier(vfs_handle_struct *handle,
				       SMB_ACL_ENTRY_T entry,
				       void *qual);
static int smb_full_audit_sys_acl_set_permset(vfs_handle_struct *handle,
				     SMB_ACL_ENTRY_T entry,
				     SMB_ACL_PERMSET_T permset);
static int smb_full_audit_sys_acl_valid(vfs_handle_struct *handle,
			       SMB_ACL_T theacl );
static int smb_full_audit_sys_acl_set_file(vfs_handle_struct *handle,
				  const char *name, SMB_ACL_TYPE_T acltype,
				  SMB_ACL_T theacl);
static int smb_full_audit_sys_acl_set_fd(vfs_handle_struct *handle, files_struct *fsp,
				SMB_ACL_T theacl);
static int smb_full_audit_sys_acl_delete_def_file(vfs_handle_struct *handle,
					 const char *path);
static int smb_full_audit_sys_acl_get_perm(vfs_handle_struct *handle,
				  SMB_ACL_PERMSET_T permset,
				  SMB_ACL_PERM_T perm);
static int smb_full_audit_sys_acl_free_text(vfs_handle_struct *handle,
				   char *text);
static int smb_full_audit_sys_acl_free_acl(vfs_handle_struct *handle,
				  SMB_ACL_T posix_acl);
static int smb_full_audit_sys_acl_free_qualifier(vfs_handle_struct *handle,
					void *qualifier,
					SMB_ACL_TAG_T tagtype);
static ssize_t smb_full_audit_getxattr(struct vfs_handle_struct *handle,
			      const char *path,
			      const char *name, void *value, size_t size);
static ssize_t smb_full_audit_lgetxattr(struct vfs_handle_struct *handle,
			       const char *path, const char *name,
			       void *value, size_t size);
static ssize_t smb_full_audit_fgetxattr(struct vfs_handle_struct *handle,
			       struct files_struct *fsp,
			       const char *name, void *value, size_t size);
static ssize_t smb_full_audit_listxattr(struct vfs_handle_struct *handle,
			       const char *path, char *list, size_t size);
static ssize_t smb_full_audit_llistxattr(struct vfs_handle_struct *handle,
				const char *path, char *list, size_t size);
static ssize_t smb_full_audit_flistxattr(struct vfs_handle_struct *handle,
				struct files_struct *fsp, char *list,
				size_t size);
static int smb_full_audit_removexattr(struct vfs_handle_struct *handle,
			     const char *path,
			     const char *name);
static int smb_full_audit_lremovexattr(struct vfs_handle_struct *handle,
			      const char *path,
			      const char *name);
static int smb_full_audit_fremovexattr(struct vfs_handle_struct *handle,
			      struct files_struct *fsp,
			      const char *name);
static int smb_full_audit_setxattr(struct vfs_handle_struct *handle,
			  const char *path,
			  const char *name, const void *value, size_t size,
			  int flags);
static int smb_full_audit_lsetxattr(struct vfs_handle_struct *handle,
			   const char *path,
			   const char *name, const void *value, size_t size,
			   int flags);
static int smb_full_audit_fsetxattr(struct vfs_handle_struct *handle,
			   struct files_struct *fsp, const char *name,
			   const void *value, size_t size, int flags);

static int smb_full_audit_aio_read(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb);
static int smb_full_audit_aio_write(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb);
static ssize_t smb_full_audit_aio_return(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb);
static int smb_full_audit_aio_cancel(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb);
static int smb_full_audit_aio_error(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb);
static int smb_full_audit_aio_fsync(struct vfs_handle_struct *handle, struct files_struct *fsp, int op, SMB_STRUCT_AIOCB *aiocb);
static int smb_full_audit_aio_suspend(struct vfs_handle_struct *handle, struct files_struct *fsp, const SMB_STRUCT_AIOCB * const aiocb[], int n, const struct timespec *ts);
static bool smb_full_audit_aio_force(struct vfs_handle_struct *handle,
				     struct files_struct *fsp);

/* VFS operations */

static vfs_op_tuple audit_op_tuples[] = {

	/* Disk operations */

	{SMB_VFS_OP(smb_full_audit_connect),	SMB_VFS_OP_CONNECT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_disconnect),	SMB_VFS_OP_DISCONNECT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_disk_free),	SMB_VFS_OP_DISK_FREE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_get_quota),	SMB_VFS_OP_GET_QUOTA,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_set_quota),	SMB_VFS_OP_SET_QUOTA,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_get_shadow_copy_data), SMB_VFS_OP_GET_SHADOW_COPY_DATA,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_statvfs),	SMB_VFS_OP_STATVFS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fs_capabilities), SMB_VFS_OP_FS_CAPABILITIES,
	 SMB_VFS_LAYER_LOGGER},

	/* Directory operations */

	{SMB_VFS_OP(smb_full_audit_opendir),	SMB_VFS_OP_OPENDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_readdir),	SMB_VFS_OP_READDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_seekdir),	SMB_VFS_OP_SEEKDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_telldir),	SMB_VFS_OP_TELLDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_rewinddir),	SMB_VFS_OP_REWINDDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_mkdir),	SMB_VFS_OP_MKDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_rmdir),	SMB_VFS_OP_RMDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_closedir),	SMB_VFS_OP_CLOSEDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_init_search_op), SMB_VFS_OP_INIT_SEARCH_OP,
	 SMB_VFS_LAYER_LOGGER},

	/* File operations */

	{SMB_VFS_OP(smb_full_audit_open),	SMB_VFS_OP_OPEN,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_create_file),SMB_VFS_OP_CREATE_FILE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_close),	SMB_VFS_OP_CLOSE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_read),	SMB_VFS_OP_READ,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_pread),	SMB_VFS_OP_PREAD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_write),	SMB_VFS_OP_WRITE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_pwrite),	SMB_VFS_OP_PWRITE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lseek),	SMB_VFS_OP_LSEEK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sendfile),	SMB_VFS_OP_SENDFILE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_recvfile),	SMB_VFS_OP_RECVFILE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_rename),	SMB_VFS_OP_RENAME,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fsync),	SMB_VFS_OP_FSYNC,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_stat),	SMB_VFS_OP_STAT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fstat),	SMB_VFS_OP_FSTAT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lstat),	SMB_VFS_OP_LSTAT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_get_alloc_size),	SMB_VFS_OP_GET_ALLOC_SIZE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_unlink),	SMB_VFS_OP_UNLINK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_chmod),	SMB_VFS_OP_CHMOD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fchmod),	SMB_VFS_OP_FCHMOD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_chown),	SMB_VFS_OP_CHOWN,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fchown),	SMB_VFS_OP_FCHOWN,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lchown),	SMB_VFS_OP_LCHOWN,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_chdir),	SMB_VFS_OP_CHDIR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_getwd),	SMB_VFS_OP_GETWD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_ntimes),	SMB_VFS_OP_NTIMES,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_ftruncate),	SMB_VFS_OP_FTRUNCATE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lock),	SMB_VFS_OP_LOCK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_kernel_flock),	SMB_VFS_OP_KERNEL_FLOCK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_linux_setlease),       SMB_VFS_OP_LINUX_SETLEASE,
         SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_getlock),	SMB_VFS_OP_GETLOCK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_symlink),	SMB_VFS_OP_SYMLINK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_readlink),	SMB_VFS_OP_READLINK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_link),	SMB_VFS_OP_LINK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_mknod),	SMB_VFS_OP_MKNOD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_realpath),	SMB_VFS_OP_REALPATH,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_notify_watch),SMB_VFS_OP_NOTIFY_WATCH,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_chflags),	SMB_VFS_OP_CHFLAGS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_file_id_create),	SMB_VFS_OP_FILE_ID_CREATE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_streaminfo),	SMB_VFS_OP_STREAMINFO,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_get_real_filename), SMB_VFS_OP_GET_REAL_FILENAME,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_brl_lock_windows), SMB_VFS_OP_BRL_LOCK_WINDOWS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_brl_unlock_windows), SMB_VFS_OP_BRL_UNLOCK_WINDOWS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_brl_cancel_windows), SMB_VFS_OP_BRL_CANCEL_WINDOWS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_strict_lock), SMB_VFS_OP_STRICT_LOCK,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_strict_unlock), SMB_VFS_OP_STRICT_UNLOCK,
	 SMB_VFS_LAYER_LOGGER},

	/* NT ACL operations. */

	{SMB_VFS_OP(smb_full_audit_fget_nt_acl),	SMB_VFS_OP_FGET_NT_ACL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_get_nt_acl),	SMB_VFS_OP_GET_NT_ACL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fset_nt_acl),	SMB_VFS_OP_FSET_NT_ACL,
	 SMB_VFS_LAYER_LOGGER},

	/* POSIX ACL operations. */

	{SMB_VFS_OP(smb_full_audit_chmod_acl),	SMB_VFS_OP_CHMOD_ACL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fchmod_acl),	SMB_VFS_OP_FCHMOD_ACL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_entry),	SMB_VFS_OP_SYS_ACL_GET_ENTRY,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_tag_type),	SMB_VFS_OP_SYS_ACL_GET_TAG_TYPE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_permset),	SMB_VFS_OP_SYS_ACL_GET_PERMSET,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_qualifier),	SMB_VFS_OP_SYS_ACL_GET_QUALIFIER,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_file),	SMB_VFS_OP_SYS_ACL_GET_FILE,
	 SMB_VFS_LAYER_LOGGER},
{SMB_VFS_OP(smb_full_audit_sys_acl_get_fd),	SMB_VFS_OP_SYS_ACL_GET_FD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_clear_perms),	SMB_VFS_OP_SYS_ACL_CLEAR_PERMS,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_add_perm),	SMB_VFS_OP_SYS_ACL_ADD_PERM,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_to_text),	SMB_VFS_OP_SYS_ACL_TO_TEXT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_init),	SMB_VFS_OP_SYS_ACL_INIT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_create_entry),	SMB_VFS_OP_SYS_ACL_CREATE_ENTRY,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_set_tag_type),	SMB_VFS_OP_SYS_ACL_SET_TAG_TYPE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_set_qualifier),	SMB_VFS_OP_SYS_ACL_SET_QUALIFIER,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_set_permset),	SMB_VFS_OP_SYS_ACL_SET_PERMSET,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_valid),	SMB_VFS_OP_SYS_ACL_VALID,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_set_file),	SMB_VFS_OP_SYS_ACL_SET_FILE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_set_fd),	SMB_VFS_OP_SYS_ACL_SET_FD,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_delete_def_file),	SMB_VFS_OP_SYS_ACL_DELETE_DEF_FILE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_get_perm),	SMB_VFS_OP_SYS_ACL_GET_PERM,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_free_text),	SMB_VFS_OP_SYS_ACL_FREE_TEXT,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_free_acl),	SMB_VFS_OP_SYS_ACL_FREE_ACL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_sys_acl_free_qualifier),	SMB_VFS_OP_SYS_ACL_FREE_QUALIFIER,
	 SMB_VFS_LAYER_LOGGER},

	/* EA operations. */

	{SMB_VFS_OP(smb_full_audit_getxattr),	SMB_VFS_OP_GETXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lgetxattr),	SMB_VFS_OP_LGETXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fgetxattr),	SMB_VFS_OP_FGETXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_listxattr),	SMB_VFS_OP_LISTXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_llistxattr),	SMB_VFS_OP_LLISTXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_flistxattr),	SMB_VFS_OP_FLISTXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_removexattr),	SMB_VFS_OP_REMOVEXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lremovexattr),	SMB_VFS_OP_LREMOVEXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fremovexattr),	SMB_VFS_OP_FREMOVEXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_setxattr),	SMB_VFS_OP_SETXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_lsetxattr),	SMB_VFS_OP_LSETXATTR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_fsetxattr),	SMB_VFS_OP_FSETXATTR,
	 SMB_VFS_LAYER_LOGGER},

	{SMB_VFS_OP(smb_full_audit_aio_read),	SMB_VFS_OP_AIO_READ,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_write),	SMB_VFS_OP_AIO_WRITE,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_return),	SMB_VFS_OP_AIO_RETURN,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_cancel), SMB_VFS_OP_AIO_CANCEL,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_error),	SMB_VFS_OP_AIO_ERROR,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_fsync),	SMB_VFS_OP_AIO_FSYNC,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_suspend),SMB_VFS_OP_AIO_SUSPEND,
	 SMB_VFS_LAYER_LOGGER},
	{SMB_VFS_OP(smb_full_audit_aio_force),SMB_VFS_OP_AIO_FORCE,
	 SMB_VFS_LAYER_LOGGER},

	/* Finish VFS operations definition */

	{SMB_VFS_OP(NULL),		SMB_VFS_OP_NOOP,
	 SMB_VFS_LAYER_NOOP}
};

/* The following array *must* be in the same order as defined in vfs.h */

static struct {
	vfs_op_type type;
	const char *name;
} vfs_op_names[] = {
	{ SMB_VFS_OP_CONNECT,	"connect" },
	{ SMB_VFS_OP_DISCONNECT,	"disconnect" },
	{ SMB_VFS_OP_DISK_FREE,	"disk_free" },
	{ SMB_VFS_OP_GET_QUOTA,	"get_quota" },
	{ SMB_VFS_OP_SET_QUOTA,	"set_quota" },
	{ SMB_VFS_OP_GET_SHADOW_COPY_DATA,	"get_shadow_copy_data" },
	{ SMB_VFS_OP_STATVFS,	"statvfs" },
	{ SMB_VFS_OP_FS_CAPABILITIES,	"fs_capabilities" },
	{ SMB_VFS_OP_OPENDIR,	"opendir" },
	{ SMB_VFS_OP_READDIR,	"readdir" },
	{ SMB_VFS_OP_SEEKDIR,   "seekdir" },
	{ SMB_VFS_OP_TELLDIR,   "telldir" },
	{ SMB_VFS_OP_REWINDDIR, "rewinddir" },
	{ SMB_VFS_OP_MKDIR,	"mkdir" },
	{ SMB_VFS_OP_RMDIR,	"rmdir" },
	{ SMB_VFS_OP_CLOSEDIR,	"closedir" },
	{ SMB_VFS_OP_INIT_SEARCH_OP, "init_search_op" },
	{ SMB_VFS_OP_OPEN,	"open" },
	{ SMB_VFS_OP_CREATE_FILE, "create_file" },
	{ SMB_VFS_OP_CLOSE,	"close" },
	{ SMB_VFS_OP_READ,	"read" },
	{ SMB_VFS_OP_PREAD,	"pread" },
	{ SMB_VFS_OP_WRITE,	"write" },
	{ SMB_VFS_OP_PWRITE,	"pwrite" },
	{ SMB_VFS_OP_LSEEK,	"lseek" },
	{ SMB_VFS_OP_SENDFILE,	"sendfile" },
	{ SMB_VFS_OP_RECVFILE,  "recvfile" },
	{ SMB_VFS_OP_RENAME,	"rename" },
	{ SMB_VFS_OP_FSYNC,	"fsync" },
	{ SMB_VFS_OP_STAT,	"stat" },
	{ SMB_VFS_OP_FSTAT,	"fstat" },
	{ SMB_VFS_OP_LSTAT,	"lstat" },
	{ SMB_VFS_OP_GET_ALLOC_SIZE,	"get_alloc_size" },
	{ SMB_VFS_OP_UNLINK,	"unlink" },
	{ SMB_VFS_OP_CHMOD,	"chmod" },
	{ SMB_VFS_OP_FCHMOD,	"fchmod" },
	{ SMB_VFS_OP_CHOWN,	"chown" },
	{ SMB_VFS_OP_FCHOWN,	"fchown" },
	{ SMB_VFS_OP_LCHOWN,	"lchown" },
	{ SMB_VFS_OP_CHDIR,	"chdir" },
	{ SMB_VFS_OP_GETWD,	"getwd" },
	{ SMB_VFS_OP_NTIMES,	"ntimes" },
	{ SMB_VFS_OP_FTRUNCATE,	"ftruncate" },
	{ SMB_VFS_OP_LOCK,	"lock" },
	{ SMB_VFS_OP_KERNEL_FLOCK,	"kernel_flock" },
	{ SMB_VFS_OP_LINUX_SETLEASE, "linux_setlease" },
	{ SMB_VFS_OP_GETLOCK,	"getlock" },
	{ SMB_VFS_OP_SYMLINK,	"symlink" },
	{ SMB_VFS_OP_READLINK,	"readlink" },
	{ SMB_VFS_OP_LINK,	"link" },
	{ SMB_VFS_OP_MKNOD,	"mknod" },
	{ SMB_VFS_OP_REALPATH,	"realpath" },
	{ SMB_VFS_OP_NOTIFY_WATCH, "notify_watch" },
	{ SMB_VFS_OP_CHFLAGS,	"chflags" },
	{ SMB_VFS_OP_FILE_ID_CREATE,	"file_id_create" },
	{ SMB_VFS_OP_STREAMINFO,	"streaminfo" },
	{ SMB_VFS_OP_GET_REAL_FILENAME, "get_real_filename" },
	{ SMB_VFS_OP_BRL_LOCK_WINDOWS,  "brl_lock_windows" },
	{ SMB_VFS_OP_BRL_UNLOCK_WINDOWS, "brl_unlock_windows" },
	{ SMB_VFS_OP_BRL_CANCEL_WINDOWS, "brl_cancel_windows" },
	{ SMB_VFS_OP_STRICT_LOCK, "strict_lock" },
	{ SMB_VFS_OP_STRICT_UNLOCK, "strict_unlock" },
	{ SMB_VFS_OP_FGET_NT_ACL,	"fget_nt_acl" },
	{ SMB_VFS_OP_GET_NT_ACL,	"get_nt_acl" },
	{ SMB_VFS_OP_FSET_NT_ACL,	"fset_nt_acl" },
	{ SMB_VFS_OP_CHMOD_ACL,	"chmod_acl" },
	{ SMB_VFS_OP_FCHMOD_ACL,	"fchmod_acl" },
	{ SMB_VFS_OP_SYS_ACL_GET_ENTRY,	"sys_acl_get_entry" },
	{ SMB_VFS_OP_SYS_ACL_GET_TAG_TYPE,	"sys_acl_get_tag_type" },
	{ SMB_VFS_OP_SYS_ACL_GET_PERMSET,	"sys_acl_get_permset" },
	{ SMB_VFS_OP_SYS_ACL_GET_QUALIFIER,	"sys_acl_get_qualifier" },
	{ SMB_VFS_OP_SYS_ACL_GET_FILE,	"sys_acl_get_file" },
	{ SMB_VFS_OP_SYS_ACL_GET_FD,	"sys_acl_get_fd" },
	{ SMB_VFS_OP_SYS_ACL_CLEAR_PERMS,	"sys_acl_clear_perms" },
	{ SMB_VFS_OP_SYS_ACL_ADD_PERM,	"sys_acl_add_perm" },
	{ SMB_VFS_OP_SYS_ACL_TO_TEXT,	"sys_acl_to_text" },
	{ SMB_VFS_OP_SYS_ACL_INIT,	"sys_acl_init" },
	{ SMB_VFS_OP_SYS_ACL_CREATE_ENTRY,	"sys_acl_create_entry" },
	{ SMB_VFS_OP_SYS_ACL_SET_TAG_TYPE,	"sys_acl_set_tag_type" },
	{ SMB_VFS_OP_SYS_ACL_SET_QUALIFIER,	"sys_acl_set_qualifier" },
	{ SMB_VFS_OP_SYS_ACL_SET_PERMSET,	"sys_acl_set_permset" },
	{ SMB_VFS_OP_SYS_ACL_VALID,	"sys_acl_valid" },
	{ SMB_VFS_OP_SYS_ACL_SET_FILE,	"sys_acl_set_file" },
	{ SMB_VFS_OP_SYS_ACL_SET_FD,	"sys_acl_set_fd" },
	{ SMB_VFS_OP_SYS_ACL_DELETE_DEF_FILE,	"sys_acl_delete_def_file" },
	{ SMB_VFS_OP_SYS_ACL_GET_PERM,	"sys_acl_get_perm" },
	{ SMB_VFS_OP_SYS_ACL_FREE_TEXT,	"sys_acl_free_text" },
	{ SMB_VFS_OP_SYS_ACL_FREE_ACL,	"sys_acl_free_acl" },
	{ SMB_VFS_OP_SYS_ACL_FREE_QUALIFIER,	"sys_acl_free_qualifier" },
	{ SMB_VFS_OP_GETXATTR,	"getxattr" },
	{ SMB_VFS_OP_LGETXATTR,	"lgetxattr" },
	{ SMB_VFS_OP_FGETXATTR,	"fgetxattr" },
	{ SMB_VFS_OP_LISTXATTR,	"listxattr" },
	{ SMB_VFS_OP_LLISTXATTR,	"llistxattr" },
	{ SMB_VFS_OP_FLISTXATTR,	"flistxattr" },
	{ SMB_VFS_OP_REMOVEXATTR,	"removexattr" },
	{ SMB_VFS_OP_LREMOVEXATTR,	"lremovexattr" },
	{ SMB_VFS_OP_FREMOVEXATTR,	"fremovexattr" },
	{ SMB_VFS_OP_SETXATTR,	"setxattr" },
	{ SMB_VFS_OP_LSETXATTR,	"lsetxattr" },
	{ SMB_VFS_OP_FSETXATTR,	"fsetxattr" },
	{ SMB_VFS_OP_AIO_READ,	"aio_read" },
	{ SMB_VFS_OP_AIO_WRITE,	"aio_write" },
	{ SMB_VFS_OP_AIO_RETURN,"aio_return" },
	{ SMB_VFS_OP_AIO_CANCEL,"aio_cancel" },
	{ SMB_VFS_OP_AIO_ERROR,	"aio_error" },
	{ SMB_VFS_OP_AIO_FSYNC,	"aio_fsync" },
	{ SMB_VFS_OP_AIO_SUSPEND,"aio_suspend" },
	{ SMB_VFS_OP_AIO_FORCE, "aio_force" },
	{ SMB_VFS_OP_IS_OFFLINE, "aio_is_offline" },
	{ SMB_VFS_OP_SET_OFFLINE, "aio_set_offline" },
	{ SMB_VFS_OP_LAST, NULL }
};

static int audit_syslog_facility(vfs_handle_struct *handle)
{
	static const struct enum_list enum_log_facilities[] = {
		{ LOG_USER, "USER" },
		{ LOG_LOCAL0, "LOCAL0" },
		{ LOG_LOCAL1, "LOCAL1" },
		{ LOG_LOCAL2, "LOCAL2" },
		{ LOG_LOCAL3, "LOCAL3" },
		{ LOG_LOCAL4, "LOCAL4" },
		{ LOG_LOCAL5, "LOCAL5" },
		{ LOG_LOCAL6, "LOCAL6" },
		{ LOG_LOCAL7, "LOCAL7" }
	};

	int facility;

	facility = lp_parm_enum(SNUM(handle->conn), "full_audit", "facility", enum_log_facilities, LOG_USER);

	return facility;
}

static int audit_syslog_priority(vfs_handle_struct *handle)
{
	static const struct enum_list enum_log_priorities[] = {
		{ LOG_EMERG, "EMERG" },
		{ LOG_ALERT, "ALERT" },
		{ LOG_CRIT, "CRIT" },
		{ LOG_ERR, "ERR" },
		{ LOG_WARNING, "WARNING" },
		{ LOG_NOTICE, "NOTICE" },
		{ LOG_INFO, "INFO" },
		{ LOG_DEBUG, "DEBUG" }
	};

	int priority;

	priority = lp_parm_enum(SNUM(handle->conn), "full_audit", "priority",
				enum_log_priorities, LOG_NOTICE);
	if (priority == -1) {
		priority = LOG_WARNING;
	}

	return priority;
}

static char *audit_prefix(TALLOC_CTX *ctx, connection_struct *conn)
{
	char *prefix = NULL;
	char *result;

	prefix = talloc_strdup(ctx,
			lp_parm_const_string(SNUM(conn), "full_audit",
					     "prefix", "%u|%I"));
	if (!prefix) {
		return NULL;
	}
	result = talloc_sub_advanced(ctx,
			lp_servicename(SNUM(conn)),
			conn->server_info->unix_name,
			conn->connectpath,
			conn->server_info->utok.gid,
			conn->server_info->sanitized_username,
			pdb_get_domain(conn->server_info->sam_account),
			prefix);
	TALLOC_FREE(prefix);
	return result;
}

static bool log_success(vfs_handle_struct *handle, vfs_op_type op)
{
	struct vfs_full_audit_private_data *pd = NULL;

	SMB_VFS_HANDLE_GET_DATA(handle, pd,
		struct vfs_full_audit_private_data,
		return True);

	if (pd->success_ops == NULL) {
		return True;
	}

	return bitmap_query(pd->success_ops, op);
}

static bool log_failure(vfs_handle_struct *handle, vfs_op_type op)
{
	struct vfs_full_audit_private_data *pd = NULL;

	SMB_VFS_HANDLE_GET_DATA(handle, pd,
		struct vfs_full_audit_private_data,
		return True);

	if (pd->failure_ops == NULL)
		return True;

	return bitmap_query(pd->failure_ops, op);
}

static void init_bitmap(struct bitmap **bm, const char **ops)
{
	bool log_all = False;

	if (*bm != NULL)
		return;

	*bm = bitmap_allocate(SMB_VFS_OP_LAST);

	if (*bm == NULL) {
		DEBUG(0, ("Could not alloc bitmap -- "
			  "defaulting to logging everything\n"));
		return;
	}

	while (*ops != NULL) {
		int i;
		bool found = False;

		if (strequal(*ops, "all")) {
			log_all = True;
			break;
		}

		if (strequal(*ops, "none")) {
			break;
		}

		for (i=0; i<SMB_VFS_OP_LAST; i++) {
			if (vfs_op_names[i].name == NULL) {
				smb_panic("vfs_full_audit.c: name table not "
					  "in sync with vfs.h\n");
			}

			if (strequal(*ops, vfs_op_names[i].name)) {
				bitmap_set(*bm, i);
				found = True;
			}
		}
		if (!found) {
			DEBUG(0, ("Could not find opname %s, logging all\n",
				  *ops));
			log_all = True;
			break;
		}
		ops += 1;
	}

	if (log_all) {
		/* The query functions default to True */
		bitmap_free(*bm);
		*bm = NULL;
	}
}

static const char *audit_opname(vfs_op_type op)
{
	if (op >= SMB_VFS_OP_LAST)
		return "INVALID VFS OP";
	return vfs_op_names[op].name;
}

static void do_log(vfs_op_type op, bool success, vfs_handle_struct *handle,
		   const char *format, ...)
{
	fstring err_msg;
	char *audit_pre = NULL;
	va_list ap;
	char *op_msg = NULL;

	if (success && (!log_success(handle, op)))
		return;

	if (!success && (!log_failure(handle, op)))
		return;

	if (success)
		fstrcpy(err_msg, "ok");
	else
		fstr_sprintf(err_msg, "fail (%s)", strerror(errno));

	va_start(ap, format);
	op_msg = talloc_vasprintf(talloc_tos(), format, ap);
	va_end(ap);

	if (!op_msg) {
		return;
	}

	audit_pre = audit_prefix(talloc_tos(), handle->conn);
	syslog(audit_syslog_priority(handle), "%s|%s|%s|%s\n",
		audit_pre ? audit_pre : "",
		audit_opname(op), err_msg, op_msg);

	TALLOC_FREE(audit_pre);
	TALLOC_FREE(op_msg);

	return;
}

/* Free function for the private data. */

static void free_private_data(void **p_data)
{
	struct vfs_full_audit_private_data *pd = *(struct vfs_full_audit_private_data **)p_data;

	if (pd->success_ops) {
		bitmap_free(pd->success_ops);
	}
	if (pd->failure_ops) {
		bitmap_free(pd->failure_ops);
	}
	SAFE_FREE(pd);
	*p_data = NULL;
}

/* Implementation of vfs_ops.  Pass everything on to the default
   operation but log event first. */

static int smb_full_audit_connect(vfs_handle_struct *handle,
			 const char *svc, const char *user)
{
	int result;
	struct vfs_full_audit_private_data *pd = NULL;
	const char *none[] = { NULL };
	const char *all [] = { "all" };

	if (!handle) {
		return -1;
	}

	pd = SMB_MALLOC_P(struct vfs_full_audit_private_data);
	if (!pd) {
		return -1;
	}
	ZERO_STRUCTP(pd);

	openlog("smbd_audit", 0, audit_syslog_facility(handle));

	init_bitmap(&pd->success_ops,
		    lp_parm_string_list(SNUM(handle->conn), "full_audit", "success",
					none));
	init_bitmap(&pd->failure_ops,
		    lp_parm_string_list(SNUM(handle->conn), "full_audit", "failure",
					all));

	/* Store the private data. */
	SMB_VFS_HANDLE_SET_DATA(handle, pd, free_private_data,
				struct vfs_full_audit_private_data, return -1);

	result = SMB_VFS_NEXT_CONNECT(handle, svc, user);

	do_log(SMB_VFS_OP_CONNECT, True, handle,
	       "%s", svc);

	return result;
}

static void smb_full_audit_disconnect(vfs_handle_struct *handle)
{
	SMB_VFS_NEXT_DISCONNECT(handle);

	do_log(SMB_VFS_OP_DISCONNECT, True, handle,
	       "%s", lp_servicename(SNUM(handle->conn)));

	/* The bitmaps will be disconnected when the private
	   data is deleted. */

	return;
}

static uint64_t smb_full_audit_disk_free(vfs_handle_struct *handle,
				    const char *path,
				    bool small_query, uint64_t *bsize, 
				    uint64_t *dfree, uint64_t *dsize)
{
	uint64_t result;

	result = SMB_VFS_NEXT_DISK_FREE(handle, path, small_query, bsize,
					dfree, dsize);

	/* Don't have a reasonable notion of failure here */

	do_log(SMB_VFS_OP_DISK_FREE, True, handle, "%s", path);

	return result;
}

static int smb_full_audit_get_quota(struct vfs_handle_struct *handle,
			   enum SMB_QUOTA_TYPE qtype, unid_t id,
			   SMB_DISK_QUOTA *qt)
{
	int result;

	result = SMB_VFS_NEXT_GET_QUOTA(handle, qtype, id, qt);

	do_log(SMB_VFS_OP_GET_QUOTA, (result >= 0), handle, "");

	return result;
}

	
static int smb_full_audit_set_quota(struct vfs_handle_struct *handle,
			   enum SMB_QUOTA_TYPE qtype, unid_t id,
			   SMB_DISK_QUOTA *qt)
{
	int result;

	result = SMB_VFS_NEXT_SET_QUOTA(handle, qtype, id, qt);

	do_log(SMB_VFS_OP_SET_QUOTA, (result >= 0), handle, "");

	return result;
}

static int smb_full_audit_get_shadow_copy_data(struct vfs_handle_struct *handle,
				struct files_struct *fsp,
				SHADOW_COPY_DATA *shadow_copy_data, bool labels)
{
	int result;

	result = SMB_VFS_NEXT_GET_SHADOW_COPY_DATA(handle, fsp, shadow_copy_data, labels);

	do_log(SMB_VFS_OP_GET_SHADOW_COPY_DATA, (result >= 0), handle, "");

	return result;
}

static int smb_full_audit_statvfs(struct vfs_handle_struct *handle,
				const char *path,
				struct vfs_statvfs_struct *statbuf)
{
	int result;

	result = SMB_VFS_NEXT_STATVFS(handle, path, statbuf);

	do_log(SMB_VFS_OP_STATVFS, (result >= 0), handle, "");

	return result;
}

static int smb_full_audit_fs_capabilities(struct vfs_handle_struct *handle)
{
	int result;

	result = SMB_VFS_NEXT_FS_CAPABILITIES(handle);

	do_log(SMB_VFS_OP_FS_CAPABILITIES, true, handle, "");

	return result;
}

static SMB_STRUCT_DIR *smb_full_audit_opendir(vfs_handle_struct *handle,
			  const char *fname, const char *mask, uint32 attr)
{
	SMB_STRUCT_DIR *result;

	result = SMB_VFS_NEXT_OPENDIR(handle, fname, mask, attr);

	do_log(SMB_VFS_OP_OPENDIR, (result != NULL), handle, "%s", fname);

	return result;
}

static SMB_STRUCT_DIRENT *smb_full_audit_readdir(vfs_handle_struct *handle,
				    SMB_STRUCT_DIR *dirp, SMB_STRUCT_STAT *sbuf)
{
	SMB_STRUCT_DIRENT *result;

	result = SMB_VFS_NEXT_READDIR(handle, dirp, sbuf);

	/* This operation has no reasonable error condition
	 * (End of dir is also failure), so always succeed.
	 */
	do_log(SMB_VFS_OP_READDIR, True, handle, "");

	return result;
}

static void smb_full_audit_seekdir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp, long offset)
{
	SMB_VFS_NEXT_SEEKDIR(handle, dirp, offset);

	do_log(SMB_VFS_OP_SEEKDIR, True, handle, "");
	return;
}

static long smb_full_audit_telldir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp)
{
	long result;

	result = SMB_VFS_NEXT_TELLDIR(handle, dirp);

	do_log(SMB_VFS_OP_TELLDIR, True, handle, "");

	return result;
}

static void smb_full_audit_rewinddir(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp)
{
	SMB_VFS_NEXT_REWINDDIR(handle, dirp);

	do_log(SMB_VFS_OP_REWINDDIR, True, handle, "");
	return;
}

static int smb_full_audit_mkdir(vfs_handle_struct *handle,
		       const char *path, mode_t mode)
{
	int result;
	
	result = SMB_VFS_NEXT_MKDIR(handle, path, mode);
	
	do_log(SMB_VFS_OP_MKDIR, (result >= 0), handle, "%s", path);

	return result;
}

static int smb_full_audit_rmdir(vfs_handle_struct *handle,
		       const char *path)
{
	int result;
	
	result = SMB_VFS_NEXT_RMDIR(handle, path);

	do_log(SMB_VFS_OP_RMDIR, (result >= 0), handle, "%s", path);

	return result;
}

static int smb_full_audit_closedir(vfs_handle_struct *handle,
			  SMB_STRUCT_DIR *dirp)
{
	int result;

	result = SMB_VFS_NEXT_CLOSEDIR(handle, dirp);
	
	do_log(SMB_VFS_OP_CLOSEDIR, (result >= 0), handle, "");

	return result;
}

static void smb_full_audit_init_search_op(vfs_handle_struct *handle,
			SMB_STRUCT_DIR *dirp)
{
	SMB_VFS_NEXT_INIT_SEARCH_OP(handle, dirp);

	do_log(SMB_VFS_OP_INIT_SEARCH_OP, True, handle, "");
	return;
}

static int smb_full_audit_open(vfs_handle_struct *handle,
		      const char *fname, files_struct *fsp, int flags, mode_t mode)
{
	int result;
	
	result = SMB_VFS_NEXT_OPEN(handle, fname, fsp, flags, mode);

	do_log(SMB_VFS_OP_OPEN, (result >= 0), handle, "%s|%s",
	       ((flags & O_WRONLY) || (flags & O_RDWR))?"w":"r",
	       fname);

	return result;
}

static NTSTATUS smb_full_audit_create_file(vfs_handle_struct *handle,
				      struct smb_request *req,
				      uint16_t root_dir_fid,
				      const char *fname,
				      uint32_t create_file_flags,
				      uint32_t access_mask,
				      uint32_t share_access,
				      uint32_t create_disposition,
				      uint32_t create_options,
				      uint32_t file_attributes,
				      uint32_t oplock_request,
				      uint64_t allocation_size,
				      struct security_descriptor *sd,
				      struct ea_list *ea_list,
				      files_struct **result_fsp,
				      int *pinfo,
				      SMB_STRUCT_STAT *psbuf)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_CREATE_FILE(
		handle,					/* handle */
		req,					/* req */
		root_dir_fid,				/* root_dir_fid */
		fname,					/* fname */
		create_file_flags,			/* create_file_flags */
		access_mask,				/* access_mask */
		share_access,				/* share_access */
		create_disposition,			/* create_disposition*/
		create_options,				/* create_options */
		file_attributes,			/* file_attributes */
		oplock_request,				/* oplock_request */
		allocation_size,			/* allocation_size */
		sd,					/* sd */
		ea_list,				/* ea_list */
		result_fsp,				/* result */
		pinfo,					/* pinfo */
		psbuf);					/* psbuf */

	do_log(SMB_VFS_OP_CREATE_FILE, (NT_STATUS_IS_OK(result)), handle, "0x%x|%s",
	       access_mask, fname);

	return result;
}

static int smb_full_audit_close(vfs_handle_struct *handle, files_struct *fsp)
{
	int result;
	
	result = SMB_VFS_NEXT_CLOSE(handle, fsp);

	do_log(SMB_VFS_OP_CLOSE, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_read(vfs_handle_struct *handle, files_struct *fsp,
			  void *data, size_t n)
{
	ssize_t result;

	result = SMB_VFS_NEXT_READ(handle, fsp, data, n);

	do_log(SMB_VFS_OP_READ, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_pread(vfs_handle_struct *handle, files_struct *fsp,
			   void *data, size_t n, SMB_OFF_T offset)
{
	ssize_t result;

	result = SMB_VFS_NEXT_PREAD(handle, fsp, data, n, offset);

	do_log(SMB_VFS_OP_PREAD, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_write(vfs_handle_struct *handle, files_struct *fsp,
			   const void *data, size_t n)
{
	ssize_t result;

	result = SMB_VFS_NEXT_WRITE(handle, fsp, data, n);

	do_log(SMB_VFS_OP_WRITE, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_pwrite(vfs_handle_struct *handle, files_struct *fsp,
			    const void *data, size_t n,
			    SMB_OFF_T offset)
{
	ssize_t result;

	result = SMB_VFS_NEXT_PWRITE(handle, fsp, data, n, offset);

	do_log(SMB_VFS_OP_PWRITE, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static SMB_OFF_T smb_full_audit_lseek(vfs_handle_struct *handle, files_struct *fsp,
			     SMB_OFF_T offset, int whence)
{
	ssize_t result;

	result = SMB_VFS_NEXT_LSEEK(handle, fsp, offset, whence);

	do_log(SMB_VFS_OP_LSEEK, (result != (ssize_t)-1), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_sendfile(vfs_handle_struct *handle, int tofd,
			      files_struct *fromfsp,
			      const DATA_BLOB *hdr, SMB_OFF_T offset,
			      size_t n)
{
	ssize_t result;

	result = SMB_VFS_NEXT_SENDFILE(handle, tofd, fromfsp, hdr, offset, n);

	do_log(SMB_VFS_OP_SENDFILE, (result >= 0), handle,
	       "%s", fromfsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_recvfile(vfs_handle_struct *handle, int fromfd,
		      files_struct *tofsp,
			      SMB_OFF_T offset,
			      size_t n)
{
	ssize_t result;

	result = SMB_VFS_NEXT_RECVFILE(handle, fromfd, tofsp, offset, n);

	do_log(SMB_VFS_OP_RECVFILE, (result >= 0), handle,
	       "%s", tofsp->fsp_name);

	return result;
}

static int smb_full_audit_rename(vfs_handle_struct *handle,
			const char *oldname, const char *newname)
{
	int result;
	
	result = SMB_VFS_NEXT_RENAME(handle, oldname, newname);

	do_log(SMB_VFS_OP_RENAME, (result >= 0), handle, "%s|%s", oldname, newname);

	return result;    
}

static int smb_full_audit_fsync(vfs_handle_struct *handle, files_struct *fsp)
{
	int result;
	
	result = SMB_VFS_NEXT_FSYNC(handle, fsp);

	do_log(SMB_VFS_OP_FSYNC, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;    
}

static int smb_full_audit_stat(vfs_handle_struct *handle,
		      const char *fname, SMB_STRUCT_STAT *sbuf)
{
	int result;
	
	result = SMB_VFS_NEXT_STAT(handle, fname, sbuf);

	do_log(SMB_VFS_OP_STAT, (result >= 0), handle, "%s", fname);

	return result;    
}

static int smb_full_audit_fstat(vfs_handle_struct *handle, files_struct *fsp,
		       SMB_STRUCT_STAT *sbuf)
{
	int result;
	
	result = SMB_VFS_NEXT_FSTAT(handle, fsp, sbuf);

	do_log(SMB_VFS_OP_FSTAT, (result >= 0), handle, "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_lstat(vfs_handle_struct *handle,
		       const char *path, SMB_STRUCT_STAT *sbuf)
{
	int result;
	
	result = SMB_VFS_NEXT_LSTAT(handle, path, sbuf);

	do_log(SMB_VFS_OP_LSTAT, (result >= 0), handle, "%s", path);

	return result;    
}

static int smb_full_audit_get_alloc_size(vfs_handle_struct *handle,
		       files_struct *fsp, const SMB_STRUCT_STAT *sbuf)
{
	int result;

	result = SMB_VFS_NEXT_GET_ALLOC_SIZE(handle, fsp, sbuf);

	do_log(SMB_VFS_OP_GET_ALLOC_SIZE, (result >= 0), handle, "%d", result);

	return result;
}

static int smb_full_audit_unlink(vfs_handle_struct *handle,
			const char *path)
{
	int result;
	
	result = SMB_VFS_NEXT_UNLINK(handle, path);

	do_log(SMB_VFS_OP_UNLINK, (result >= 0), handle, "%s", path);

	return result;
}

static int smb_full_audit_chmod(vfs_handle_struct *handle,
		       const char *path, mode_t mode)
{
	int result;

	result = SMB_VFS_NEXT_CHMOD(handle, path, mode);

	do_log(SMB_VFS_OP_CHMOD, (result >= 0), handle, "%s|%o", path, mode);

	return result;
}

static int smb_full_audit_fchmod(vfs_handle_struct *handle, files_struct *fsp,
			mode_t mode)
{
	int result;
	
	result = SMB_VFS_NEXT_FCHMOD(handle, fsp, mode);

	do_log(SMB_VFS_OP_FCHMOD, (result >= 0), handle,
	       "%s|%o", fsp->fsp_name, mode);

	return result;
}

static int smb_full_audit_chown(vfs_handle_struct *handle,
		       const char *path, uid_t uid, gid_t gid)
{
	int result;

	result = SMB_VFS_NEXT_CHOWN(handle, path, uid, gid);

	do_log(SMB_VFS_OP_CHOWN, (result >= 0), handle, "%s|%ld|%ld",
	       path, (long int)uid, (long int)gid);

	return result;
}

static int smb_full_audit_fchown(vfs_handle_struct *handle, files_struct *fsp,
			uid_t uid, gid_t gid)
{
	int result;

	result = SMB_VFS_NEXT_FCHOWN(handle, fsp, uid, gid);

	do_log(SMB_VFS_OP_FCHOWN, (result >= 0), handle, "%s|%ld|%ld",
	       fsp->fsp_name, (long int)uid, (long int)gid);

	return result;
}

static int smb_full_audit_lchown(vfs_handle_struct *handle,
		       const char *path, uid_t uid, gid_t gid)
{
	int result;

	result = SMB_VFS_NEXT_LCHOWN(handle, path, uid, gid);

	do_log(SMB_VFS_OP_LCHOWN, (result >= 0), handle, "%s|%ld|%ld",
	       path, (long int)uid, (long int)gid);

	return result;
}

static int smb_full_audit_chdir(vfs_handle_struct *handle,
		       const char *path)
{
	int result;

	result = SMB_VFS_NEXT_CHDIR(handle, path);

	do_log(SMB_VFS_OP_CHDIR, (result >= 0), handle, "chdir|%s", path);

	return result;
}

static char *smb_full_audit_getwd(vfs_handle_struct *handle,
			 char *path)
{
	char *result;

	result = SMB_VFS_NEXT_GETWD(handle, path);
	
	do_log(SMB_VFS_OP_GETWD, (result != NULL), handle, "%s", path);

	return result;
}

static int smb_full_audit_ntimes(vfs_handle_struct *handle,
		       const char *path, struct smb_file_time *ft)
{
	int result;

	result = SMB_VFS_NEXT_NTIMES(handle, path, ft);

	do_log(SMB_VFS_OP_NTIMES, (result >= 0), handle, "%s", path);

	return result;
}

static int smb_full_audit_ftruncate(vfs_handle_struct *handle, files_struct *fsp,
			   SMB_OFF_T len)
{
	int result;

	result = SMB_VFS_NEXT_FTRUNCATE(handle, fsp, len);

	do_log(SMB_VFS_OP_FTRUNCATE, (result >= 0), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static bool smb_full_audit_lock(vfs_handle_struct *handle, files_struct *fsp,
		       int op, SMB_OFF_T offset, SMB_OFF_T count, int type)
{
	bool result;

	result = SMB_VFS_NEXT_LOCK(handle, fsp, op, offset, count, type);

	do_log(SMB_VFS_OP_LOCK, result, handle, "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_kernel_flock(struct vfs_handle_struct *handle,
				       struct files_struct *fsp,
				       uint32 share_mode)
{
	int result;

	result = SMB_VFS_NEXT_KERNEL_FLOCK(handle, fsp, share_mode);

	do_log(SMB_VFS_OP_KERNEL_FLOCK, (result >= 0), handle, "%s",
	       fsp->fsp_name);

	return result;
}

static int smb_full_audit_linux_setlease(vfs_handle_struct *handle, files_struct *fsp,
                                 int leasetype)
{
        int result;

        result = SMB_VFS_NEXT_LINUX_SETLEASE(handle, fsp, leasetype);

        do_log(SMB_VFS_OP_LINUX_SETLEASE, (result >= 0), handle, "%s",
               fsp->fsp_name);

        return result;
}

static bool smb_full_audit_getlock(vfs_handle_struct *handle, files_struct *fsp,
		       SMB_OFF_T *poffset, SMB_OFF_T *pcount, int *ptype, pid_t *ppid)
{
	bool result;

	result = SMB_VFS_NEXT_GETLOCK(handle, fsp, poffset, pcount, ptype, ppid);

	do_log(SMB_VFS_OP_GETLOCK, result, handle, "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_symlink(vfs_handle_struct *handle,
			 const char *oldpath, const char *newpath)
{
	int result;

	result = SMB_VFS_NEXT_SYMLINK(handle, oldpath, newpath);

	do_log(SMB_VFS_OP_SYMLINK, (result >= 0), handle,
	       "%s|%s", oldpath, newpath);

	return result;
}

static int smb_full_audit_readlink(vfs_handle_struct *handle,
			  const char *path, char *buf, size_t bufsiz)
{
	int result;

	result = SMB_VFS_NEXT_READLINK(handle, path, buf, bufsiz);

	do_log(SMB_VFS_OP_READLINK, (result >= 0), handle, "%s", path);

	return result;
}

static int smb_full_audit_link(vfs_handle_struct *handle,
		      const char *oldpath, const char *newpath)
{
	int result;

	result = SMB_VFS_NEXT_LINK(handle, oldpath, newpath);

	do_log(SMB_VFS_OP_LINK, (result >= 0), handle,
	       "%s|%s", oldpath, newpath);

	return result;
}

static int smb_full_audit_mknod(vfs_handle_struct *handle,
		       const char *pathname, mode_t mode, SMB_DEV_T dev)
{
	int result;

	result = SMB_VFS_NEXT_MKNOD(handle, pathname, mode, dev);

	do_log(SMB_VFS_OP_MKNOD, (result >= 0), handle, "%s", pathname);

	return result;
}

static char *smb_full_audit_realpath(vfs_handle_struct *handle,
			    const char *path, char *resolved_path)
{
	char *result;

	result = SMB_VFS_NEXT_REALPATH(handle, path, resolved_path);

	do_log(SMB_VFS_OP_REALPATH, (result != NULL), handle, "%s", path);

	return result;
}

static NTSTATUS smb_full_audit_notify_watch(struct vfs_handle_struct *handle,
			struct sys_notify_context *ctx,
			struct notify_entry *e,
			void (*callback)(struct sys_notify_context *ctx,
					void *private_data,
					struct notify_event *ev),
			void *private_data, void *handle_p)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_NOTIFY_WATCH(handle, ctx, e, callback, private_data, handle_p);

	do_log(SMB_VFS_OP_NOTIFY_WATCH, NT_STATUS_IS_OK(result), handle, "");

	return result;
}

static int smb_full_audit_chflags(vfs_handle_struct *handle,
			    const char *path, unsigned int flags)
{
	int result;

	result = SMB_VFS_NEXT_CHFLAGS(handle, path, flags);

	do_log(SMB_VFS_OP_CHFLAGS, (result != 0), handle, "%s", path);

	return result;
}

static struct file_id smb_full_audit_file_id_create(struct vfs_handle_struct *handle,
						    const SMB_STRUCT_STAT *sbuf)
{
	struct file_id id_zero;
	struct file_id result;

	ZERO_STRUCT(id_zero);

	result = SMB_VFS_NEXT_FILE_ID_CREATE(handle, sbuf);

	do_log(SMB_VFS_OP_FILE_ID_CREATE,
	       !file_id_equal(&id_zero, &result),
	       handle, "%s", file_id_string_tos(&result));

	return result;
}

static NTSTATUS smb_full_audit_streaminfo(vfs_handle_struct *handle,
					  struct files_struct *fsp,
					  const char *fname,
					  TALLOC_CTX *mem_ctx,
					  unsigned int *pnum_streams,
					  struct stream_struct **pstreams)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_STREAMINFO(handle, fsp, fname, mem_ctx,
					 pnum_streams, pstreams);

	do_log(SMB_VFS_OP_STREAMINFO, NT_STATUS_IS_OK(result), handle,
	       "%s", fname);

	return result;
}

static int smb_full_audit_get_real_filename(struct vfs_handle_struct *handle,
					    const char *path,
					    const char *name,
					    TALLOC_CTX *mem_ctx,
					    char **found_name)
{
	int result;

	result = SMB_VFS_NEXT_GET_REAL_FILENAME(handle, path, name, mem_ctx,
						found_name);

	do_log(SMB_VFS_OP_GET_REAL_FILENAME, (result == 0), handle,
	       "%s/%s->%s", path, name, (result == 0) ? "" : *found_name);

	return result;
}

static NTSTATUS smb_full_audit_brl_lock_windows(struct vfs_handle_struct *handle,
					        struct byte_range_lock *br_lck,
					        struct lock_struct *plock,
					        bool blocking_lock,
						struct blocking_lock_record *blr)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_BRL_LOCK_WINDOWS(handle, br_lck, plock,
	    blocking_lock, blr);

	do_log(SMB_VFS_OP_BRL_LOCK_WINDOWS, NT_STATUS_IS_OK(result), handle,
	    "%s:%llu-%llu. type=%d. blocking=%d", br_lck->fsp->fsp_name,
	    plock->start, plock->size, plock->lock_type, blocking_lock );

	return result;
}

static bool smb_full_audit_brl_unlock_windows(struct vfs_handle_struct *handle,
				              struct messaging_context *msg_ctx,
				              struct byte_range_lock *br_lck,
				              const struct lock_struct *plock)
{
	bool result;

	result = SMB_VFS_NEXT_BRL_UNLOCK_WINDOWS(handle, msg_ctx, br_lck,
	    plock);

	do_log(SMB_VFS_OP_BRL_UNLOCK_WINDOWS, (result == 0), handle,
	    "%s:%llu-%llu:%d", br_lck->fsp->fsp_name, plock->start,
	    plock->size, plock->lock_type);

	return result;
}

static bool smb_full_audit_brl_cancel_windows(struct vfs_handle_struct *handle,
				              struct byte_range_lock *br_lck,
					      struct lock_struct *plock,
					      struct blocking_lock_record *blr)
{
	bool result;

	result = SMB_VFS_NEXT_BRL_CANCEL_WINDOWS(handle, br_lck, plock, blr);

	do_log(SMB_VFS_OP_BRL_CANCEL_WINDOWS, (result == 0), handle,
	    "%s:%llu-%llu:%d", br_lck->fsp->fsp_name, plock->start,
	    plock->size);

	return result;
}

static bool smb_full_audit_strict_lock(struct vfs_handle_struct *handle,
				       struct files_struct *fsp,
				       struct lock_struct *plock)
{
	bool result;

	result = SMB_VFS_NEXT_STRICT_LOCK(handle, fsp, plock);

	do_log(SMB_VFS_OP_STRICT_LOCK, result, handle,
	    "%s:%llu-%llu:%d", fsp->fsp_name, plock->start,
	    plock->size);

	return result;
}

static void smb_full_audit_strict_unlock(struct vfs_handle_struct *handle,
					 struct files_struct *fsp,
					 struct lock_struct *plock)
{
	SMB_VFS_NEXT_STRICT_UNLOCK(handle, fsp, plock);

	do_log(SMB_VFS_OP_STRICT_UNLOCK, true, handle,
	    "%s:%llu-%llu:%d", fsp->fsp_name, plock->start,
	    plock->size);

	return;
}

static NTSTATUS smb_full_audit_fget_nt_acl(vfs_handle_struct *handle, files_struct *fsp,
				uint32 security_info,
				SEC_DESC **ppdesc)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_FGET_NT_ACL(handle, fsp, security_info, ppdesc);

	do_log(SMB_VFS_OP_FGET_NT_ACL, NT_STATUS_IS_OK(result), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static NTSTATUS smb_full_audit_get_nt_acl(vfs_handle_struct *handle,
					  const char *name,
					  uint32 security_info,
					  SEC_DESC **ppdesc)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_GET_NT_ACL(handle, name, security_info, ppdesc);

	do_log(SMB_VFS_OP_GET_NT_ACL, NT_STATUS_IS_OK(result), handle,
	       "%s", name);

	return result;
}

static NTSTATUS smb_full_audit_fset_nt_acl(vfs_handle_struct *handle, files_struct *fsp,
			      uint32 security_info_sent,
			      const SEC_DESC *psd)
{
	NTSTATUS result;

	result = SMB_VFS_NEXT_FSET_NT_ACL(handle, fsp, security_info_sent, psd);

	do_log(SMB_VFS_OP_FSET_NT_ACL, NT_STATUS_IS_OK(result), handle, "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_chmod_acl(vfs_handle_struct *handle,
			   const char *path, mode_t mode)
{
	int result;
	
	result = SMB_VFS_NEXT_CHMOD_ACL(handle, path, mode);

	do_log(SMB_VFS_OP_CHMOD_ACL, (result >= 0), handle,
	       "%s|%o", path, mode);

	return result;
}

static int smb_full_audit_fchmod_acl(vfs_handle_struct *handle, files_struct *fsp,
				     mode_t mode)
{
	int result;
	
	result = SMB_VFS_NEXT_FCHMOD_ACL(handle, fsp, mode);

	do_log(SMB_VFS_OP_FCHMOD_ACL, (result >= 0), handle,
	       "%s|%o", fsp->fsp_name, mode);

	return result;
}

static int smb_full_audit_sys_acl_get_entry(vfs_handle_struct *handle,

				   SMB_ACL_T theacl, int entry_id,
				   SMB_ACL_ENTRY_T *entry_p)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_ENTRY(handle, theacl, entry_id,
						entry_p);

	do_log(SMB_VFS_OP_SYS_ACL_GET_ENTRY, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_get_tag_type(vfs_handle_struct *handle,

				      SMB_ACL_ENTRY_T entry_d,
				      SMB_ACL_TAG_T *tag_type_p)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_TAG_TYPE(handle, entry_d,
						   tag_type_p);

	do_log(SMB_VFS_OP_SYS_ACL_GET_TAG_TYPE, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_get_permset(vfs_handle_struct *handle,

				     SMB_ACL_ENTRY_T entry_d,
				     SMB_ACL_PERMSET_T *permset_p)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_PERMSET(handle, entry_d,
						  permset_p);

	do_log(SMB_VFS_OP_SYS_ACL_GET_PERMSET, (result >= 0), handle,
	       "");

	return result;
}

static void * smb_full_audit_sys_acl_get_qualifier(vfs_handle_struct *handle,

					  SMB_ACL_ENTRY_T entry_d)
{
	void *result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_QUALIFIER(handle, entry_d);

	do_log(SMB_VFS_OP_SYS_ACL_GET_QUALIFIER, (result != NULL), handle,
	       "");

	return result;
}

static SMB_ACL_T smb_full_audit_sys_acl_get_file(vfs_handle_struct *handle,
					const char *path_p,
					SMB_ACL_TYPE_T type)
{
	SMB_ACL_T result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_FILE(handle, path_p, type);

	do_log(SMB_VFS_OP_SYS_ACL_GET_FILE, (result != NULL), handle,
	       "%s", path_p);

	return result;
}

static SMB_ACL_T smb_full_audit_sys_acl_get_fd(vfs_handle_struct *handle,
				      files_struct *fsp)
{
	SMB_ACL_T result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_FD(handle, fsp);

	do_log(SMB_VFS_OP_SYS_ACL_GET_FD, (result != NULL), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_sys_acl_clear_perms(vfs_handle_struct *handle,

				     SMB_ACL_PERMSET_T permset)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_CLEAR_PERMS(handle, permset);

	do_log(SMB_VFS_OP_SYS_ACL_CLEAR_PERMS, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_add_perm(vfs_handle_struct *handle,

				  SMB_ACL_PERMSET_T permset,
				  SMB_ACL_PERM_T perm)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_ADD_PERM(handle, permset, perm);

	do_log(SMB_VFS_OP_SYS_ACL_ADD_PERM, (result >= 0), handle,
	       "");

	return result;
}

static char * smb_full_audit_sys_acl_to_text(vfs_handle_struct *handle,
				    SMB_ACL_T theacl,
				    ssize_t *plen)
{
	char * result;

	result = SMB_VFS_NEXT_SYS_ACL_TO_TEXT(handle, theacl, plen);

	do_log(SMB_VFS_OP_SYS_ACL_TO_TEXT, (result != NULL), handle,
	       "");

	return result;
}

static SMB_ACL_T smb_full_audit_sys_acl_init(vfs_handle_struct *handle,

				    int count)
{
	SMB_ACL_T result;

	result = SMB_VFS_NEXT_SYS_ACL_INIT(handle, count);

	do_log(SMB_VFS_OP_SYS_ACL_INIT, (result != NULL), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_create_entry(vfs_handle_struct *handle,
				      SMB_ACL_T *pacl,
				      SMB_ACL_ENTRY_T *pentry)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_CREATE_ENTRY(handle, pacl, pentry);

	do_log(SMB_VFS_OP_SYS_ACL_CREATE_ENTRY, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_set_tag_type(vfs_handle_struct *handle,

				      SMB_ACL_ENTRY_T entry,
				      SMB_ACL_TAG_T tagtype)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_SET_TAG_TYPE(handle, entry,
						   tagtype);

	do_log(SMB_VFS_OP_SYS_ACL_SET_TAG_TYPE, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_set_qualifier(vfs_handle_struct *handle,

				       SMB_ACL_ENTRY_T entry,
				       void *qual)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_SET_QUALIFIER(handle, entry, qual);

	do_log(SMB_VFS_OP_SYS_ACL_SET_QUALIFIER, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_set_permset(vfs_handle_struct *handle,

				     SMB_ACL_ENTRY_T entry,
				     SMB_ACL_PERMSET_T permset)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_SET_PERMSET(handle, entry, permset);

	do_log(SMB_VFS_OP_SYS_ACL_SET_PERMSET, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_valid(vfs_handle_struct *handle,

			       SMB_ACL_T theacl )
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_VALID(handle, theacl);

	do_log(SMB_VFS_OP_SYS_ACL_VALID, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_set_file(vfs_handle_struct *handle,

				  const char *name, SMB_ACL_TYPE_T acltype,
				  SMB_ACL_T theacl)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_SET_FILE(handle, name, acltype,
					       theacl);

	do_log(SMB_VFS_OP_SYS_ACL_SET_FILE, (result >= 0), handle,
	       "%s", name);

	return result;
}

static int smb_full_audit_sys_acl_set_fd(vfs_handle_struct *handle, files_struct *fsp,
				SMB_ACL_T theacl)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_SET_FD(handle, fsp, theacl);

	do_log(SMB_VFS_OP_SYS_ACL_SET_FD, (result >= 0), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_sys_acl_delete_def_file(vfs_handle_struct *handle,

					 const char *path)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_DELETE_DEF_FILE(handle, path);

	do_log(SMB_VFS_OP_SYS_ACL_DELETE_DEF_FILE, (result >= 0), handle,
	       "%s", path);

	return result;
}

static int smb_full_audit_sys_acl_get_perm(vfs_handle_struct *handle,

				  SMB_ACL_PERMSET_T permset,
				  SMB_ACL_PERM_T perm)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_GET_PERM(handle, permset, perm);

	do_log(SMB_VFS_OP_SYS_ACL_GET_PERM, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_free_text(vfs_handle_struct *handle,

				   char *text)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_FREE_TEXT(handle, text);

	do_log(SMB_VFS_OP_SYS_ACL_FREE_TEXT, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_free_acl(vfs_handle_struct *handle,

				  SMB_ACL_T posix_acl)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_FREE_ACL(handle, posix_acl);

	do_log(SMB_VFS_OP_SYS_ACL_FREE_ACL, (result >= 0), handle,
	       "");

	return result;
}

static int smb_full_audit_sys_acl_free_qualifier(vfs_handle_struct *handle,
					void *qualifier,
					SMB_ACL_TAG_T tagtype)
{
	int result;

	result = SMB_VFS_NEXT_SYS_ACL_FREE_QUALIFIER(handle, qualifier,
						     tagtype);

	do_log(SMB_VFS_OP_SYS_ACL_FREE_QUALIFIER, (result >= 0), handle,
	       "");

	return result;
}

static ssize_t smb_full_audit_getxattr(struct vfs_handle_struct *handle,
			      const char *path,
			      const char *name, void *value, size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_GETXATTR(handle, path, name, value, size);

	do_log(SMB_VFS_OP_GETXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static ssize_t smb_full_audit_lgetxattr(struct vfs_handle_struct *handle,
			       const char *path, const char *name,
			       void *value, size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_LGETXATTR(handle, path, name, value, size);

	do_log(SMB_VFS_OP_LGETXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static ssize_t smb_full_audit_fgetxattr(struct vfs_handle_struct *handle,
			       struct files_struct *fsp,
			       const char *name, void *value, size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_FGETXATTR(handle, fsp, name, value, size);

	do_log(SMB_VFS_OP_FGETXATTR, (result >= 0), handle,
	       "%s|%s", fsp->fsp_name, name);

	return result;
}

static ssize_t smb_full_audit_listxattr(struct vfs_handle_struct *handle,
			       const char *path, char *list, size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_LISTXATTR(handle, path, list, size);

	do_log(SMB_VFS_OP_LISTXATTR, (result >= 0), handle, "%s", path);

	return result;
}

static ssize_t smb_full_audit_llistxattr(struct vfs_handle_struct *handle,
				const char *path, char *list, size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_LLISTXATTR(handle, path, list, size);

	do_log(SMB_VFS_OP_LLISTXATTR, (result >= 0), handle, "%s", path);

	return result;
}

static ssize_t smb_full_audit_flistxattr(struct vfs_handle_struct *handle,
				struct files_struct *fsp, char *list,
				size_t size)
{
	ssize_t result;

	result = SMB_VFS_NEXT_FLISTXATTR(handle, fsp, list, size);

	do_log(SMB_VFS_OP_FLISTXATTR, (result >= 0), handle,
	       "%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_removexattr(struct vfs_handle_struct *handle,
			     const char *path,
			     const char *name)
{
	int result;

	result = SMB_VFS_NEXT_REMOVEXATTR(handle, path, name);

	do_log(SMB_VFS_OP_REMOVEXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static int smb_full_audit_lremovexattr(struct vfs_handle_struct *handle,
			      const char *path,
			      const char *name)
{
	int result;

	result = SMB_VFS_NEXT_LREMOVEXATTR(handle, path, name);

	do_log(SMB_VFS_OP_LREMOVEXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static int smb_full_audit_fremovexattr(struct vfs_handle_struct *handle,
			      struct files_struct *fsp,
			      const char *name)
{
	int result;

	result = SMB_VFS_NEXT_FREMOVEXATTR(handle, fsp, name);

	do_log(SMB_VFS_OP_FREMOVEXATTR, (result >= 0), handle,
	       "%s|%s", fsp->fsp_name, name);

	return result;
}

static int smb_full_audit_setxattr(struct vfs_handle_struct *handle,
			  const char *path,
			  const char *name, const void *value, size_t size,
			  int flags)
{
	int result;

	result = SMB_VFS_NEXT_SETXATTR(handle, path, name, value, size,
				       flags);

	do_log(SMB_VFS_OP_SETXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static int smb_full_audit_lsetxattr(struct vfs_handle_struct *handle,
			   const char *path,
			   const char *name, const void *value, size_t size,
			   int flags)
{
	int result;

	result = SMB_VFS_NEXT_LSETXATTR(handle, path, name, value, size,
					flags);

	do_log(SMB_VFS_OP_LSETXATTR, (result >= 0), handle,
	       "%s|%s", path, name);

	return result;
}

static int smb_full_audit_fsetxattr(struct vfs_handle_struct *handle,
			   struct files_struct *fsp, const char *name,
			   const void *value, size_t size, int flags)
{
	int result;

	result = SMB_VFS_NEXT_FSETXATTR(handle, fsp, name, value, size, flags);

	do_log(SMB_VFS_OP_FSETXATTR, (result >= 0), handle,
	       "%s|%s", fsp->fsp_name, name);

	return result;
}

static int smb_full_audit_aio_read(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_READ(handle, fsp, aiocb);
	do_log(SMB_VFS_OP_AIO_READ, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_aio_write(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_WRITE(handle, fsp, aiocb);
	do_log(SMB_VFS_OP_AIO_WRITE, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static ssize_t smb_full_audit_aio_return(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_RETURN(handle, fsp, aiocb);
	do_log(SMB_VFS_OP_AIO_RETURN, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_aio_cancel(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_CANCEL(handle, fsp, aiocb);
	do_log(SMB_VFS_OP_AIO_CANCEL, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_aio_error(struct vfs_handle_struct *handle, struct files_struct *fsp, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_ERROR(handle, fsp, aiocb);
	do_log(SMB_VFS_OP_AIO_ERROR, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_aio_fsync(struct vfs_handle_struct *handle, struct files_struct *fsp, int op, SMB_STRUCT_AIOCB *aiocb)
{
	int result;

	result = SMB_VFS_NEXT_AIO_FSYNC(handle, fsp, op, aiocb);
	do_log(SMB_VFS_OP_AIO_FSYNC, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static int smb_full_audit_aio_suspend(struct vfs_handle_struct *handle, struct files_struct *fsp, const SMB_STRUCT_AIOCB * const aiocb[], int n, const struct timespec *ts)
{
	int result;

	result = SMB_VFS_NEXT_AIO_SUSPEND(handle, fsp, aiocb, n, ts);
	do_log(SMB_VFS_OP_AIO_SUSPEND, (result >= 0), handle,
		"%s", fsp->fsp_name);

	return result;
}

static bool smb_full_audit_aio_force(struct vfs_handle_struct *handle,
				     struct files_struct *fsp)
{
	bool result;

	result = SMB_VFS_NEXT_AIO_FORCE(handle, fsp);
	do_log(SMB_VFS_OP_AIO_FORCE, result, handle,
		"%s", fsp->fsp_name);

	return result;
}

NTSTATUS vfs_full_audit_init(void);
NTSTATUS vfs_full_audit_init(void)
{
	NTSTATUS ret = smb_register_vfs(SMB_VFS_INTERFACE_VERSION,
					"full_audit", audit_op_tuples);
	
	if (!NT_STATUS_IS_OK(ret))
		return ret;

	vfs_full_audit_debug_level = debug_add_class("full_audit");
	if (vfs_full_audit_debug_level == -1) {
		vfs_full_audit_debug_level = DBGC_VFS;
		DEBUG(0, ("vfs_full_audit: Couldn't register custom debugging "
			  "class!\n"));
	} else {
		DEBUG(10, ("vfs_full_audit: Debug class number of "
			   "'full_audit': %d\n", vfs_full_audit_debug_level));
	}
	
	return ret;
}
