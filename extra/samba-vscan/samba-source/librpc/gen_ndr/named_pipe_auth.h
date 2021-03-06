/* header auto-generated by pidl */

#include <stdint.h>

#include "libcli/util/ntstatus.h"

#include "librpc/gen_ndr/netlogon.h"
#ifndef _HEADER_named_pipe_auth
#define _HEADER_named_pipe_auth

#define NAMED_PIPE_AUTH_MAGIC	( "NPAM" )
union named_pipe_auth_req_info {
	struct netr_SamInfo3 info1;/* [case] */
}/* [switch_type(uint32)] */;

struct named_pipe_auth_req {
	uint32_t length;/* [value(ndr_size_named_pipe_auth_req(r,ndr->iconv_convenience,ndr->flags)-4),flag(LIBNDR_FLAG_BIGENDIAN)] */
	const char *magic;/* [value(NAMED_PIPE_AUTH_MAGIC),charset(DOS)] */
	uint32_t level;
	union named_pipe_auth_req_info info;/* [switch_is(level)] */
}/* [gensize,public] */;

union named_pipe_auth_rep_info {
	int _dummy_element;
}/* [switch_type(uint32)] */;

struct named_pipe_auth_rep {
	uint32_t length;/* [value(ndr_size_named_pipe_auth_rep(r,ndr->iconv_convenience,ndr->flags)-4),flag(LIBNDR_FLAG_BIGENDIAN)] */
	const char *magic;/* [value(NAMED_PIPE_AUTH_MAGIC),charset(DOS)] */
	uint32_t level;
	union named_pipe_auth_rep_info info;/* [switch_is(level)] */
	NTSTATUS status;
}/* [gensize,public] */;

#endif /* _HEADER_named_pipe_auth */
