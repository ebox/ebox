[SUBSYSTEM::LIBSAMBA-UTIL]
PUBLIC_DEPENDENCIES = \
		LIBTALLOC LIBCRYPTO \
		SOCKET_WRAPPER LIBREPLACE_NETWORK \
		CHARSET EXECINFO

LIBSAMBA-UTIL_OBJ_FILES = $(addprefix $(libutilsrcdir)/, \
	xfile.o \
		debug.o \
		fault.o \
		signal.o \
		system.o \
		time.o \
		genrand.o \
		dprintf.o \
		util_str.o \
		substitute.o \
		util_strlist.o \
		util_file.o \
		data_blob.o \
		util.o \
		util_net.o \
		fsusage.o \
		ms_fnmatch.o \
		mutex.o \
		idtree.o \
		become_daemon.o \
		rbtree.o \
		talloc_stack.o \
		params.o)

PUBLIC_HEADERS += $(addprefix $(libutilsrcdir)/, util.h \
				 dlinklist.h \
				 attr.h \
				 byteorder.h \
				 data_blob.h \
				 debug.h \
				 memory.h \
				 mutex.h \
				 safe_string.h \
				 time.h \
				 util_ldb.h \
				 talloc_stack.h \
				 xfile.h)

[SUBSYSTEM::ASN1_UTIL]

ASN1_UTIL_OBJ_FILES = $(libutilsrcdir)/asn1.o

[SUBSYSTEM::UNIX_PRIVS]

UNIX_PRIVS_OBJ_FILES = $(libutilsrcdir)/unix_privs.o

$(eval $(call proto_header_template,$(libutilsrcdir)/unix_privs.h,$(UNIX_PRIVS_OBJ_FILES:.o=.c)))

################################################
# Start SUBSYSTEM WRAP_XATTR
[SUBSYSTEM::WRAP_XATTR]
PUBLIC_DEPENDENCIES = XATTR
#
# End SUBSYSTEM WRAP_XATTR
################################################

WRAP_XATTR_OBJ_FILES = $(libutilsrcdir)/wrap_xattr.o

[SUBSYSTEM::UTIL_TDB]
PUBLIC_DEPENDENCIES = LIBTDB

UTIL_TDB_OBJ_FILES = $(libutilsrcdir)/util_tdb.o

[SUBSYSTEM::UTIL_LDB]
PUBLIC_DEPENDENCIES = LIBLDB

UTIL_LDB_OBJ_FILES = $(libutilsrcdir)/util_ldb.o
