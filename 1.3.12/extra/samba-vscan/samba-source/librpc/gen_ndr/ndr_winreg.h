/* header auto-generated by pidl */

#include "librpc/ndr/libndr.h"
#include "../librpc/gen_ndr/winreg.h"

#ifndef _HEADER_NDR_winreg
#define _HEADER_NDR_winreg

#define NDR_WINREG_UUID "338cd001-2244-31f1-aaaa-900038001003"
#define NDR_WINREG_VERSION 1.0
#define NDR_WINREG_NAME "winreg"
#define NDR_WINREG_HELPSTRING "Remote Registry Service"
extern const struct ndr_interface_table ndr_table_winreg;
#define NDR_WINREG_OPENHKCR (0x00)

#define NDR_WINREG_OPENHKCU (0x01)

#define NDR_WINREG_OPENHKLM (0x02)

#define NDR_WINREG_OPENHKPD (0x03)

#define NDR_WINREG_OPENHKU (0x04)

#define NDR_WINREG_CLOSEKEY (0x05)

#define NDR_WINREG_CREATEKEY (0x06)

#define NDR_WINREG_DELETEKEY (0x07)

#define NDR_WINREG_DELETEVALUE (0x08)

#define NDR_WINREG_ENUMKEY (0x09)

#define NDR_WINREG_ENUMVALUE (0x0a)

#define NDR_WINREG_FLUSHKEY (0x0b)

#define NDR_WINREG_GETKEYSECURITY (0x0c)

#define NDR_WINREG_LOADKEY (0x0d)

#define NDR_WINREG_NOTIFYCHANGEKEYVALUE (0x0e)

#define NDR_WINREG_OPENKEY (0x0f)

#define NDR_WINREG_QUERYINFOKEY (0x10)

#define NDR_WINREG_QUERYVALUE (0x11)

#define NDR_WINREG_REPLACEKEY (0x12)

#define NDR_WINREG_RESTOREKEY (0x13)

#define NDR_WINREG_SAVEKEY (0x14)

#define NDR_WINREG_SETKEYSECURITY (0x15)

#define NDR_WINREG_SETVALUE (0x16)

#define NDR_WINREG_UNLOADKEY (0x17)

#define NDR_WINREG_INITIATESYSTEMSHUTDOWN (0x18)

#define NDR_WINREG_ABORTSYSTEMSHUTDOWN (0x19)

#define NDR_WINREG_GETVERSION (0x1a)

#define NDR_WINREG_OPENHKCC (0x1b)

#define NDR_WINREG_OPENHKDD (0x1c)

#define NDR_WINREG_QUERYMULTIPLEVALUES (0x1d)

#define NDR_WINREG_INITIATESYSTEMSHUTDOWNEX (0x1e)

#define NDR_WINREG_SAVEKEYEX (0x1f)

#define NDR_WINREG_OPENHKPT (0x20)

#define NDR_WINREG_OPENHKPN (0x21)

#define NDR_WINREG_QUERYMULTIPLEVALUES2 (0x22)

#define NDR_WINREG_CALL_COUNT (35)
void ndr_print_winreg_AccessMask(struct ndr_print *ndr, const char *name, uint32_t r);
enum ndr_err_code ndr_push_winreg_Type(struct ndr_push *ndr, int ndr_flags, enum winreg_Type r);
enum ndr_err_code ndr_pull_winreg_Type(struct ndr_pull *ndr, int ndr_flags, enum winreg_Type *r);
void ndr_print_winreg_Type(struct ndr_print *ndr, const char *name, enum winreg_Type r);
enum ndr_err_code ndr_push_winreg_String(struct ndr_push *ndr, int ndr_flags, const struct winreg_String *r);
enum ndr_err_code ndr_pull_winreg_String(struct ndr_pull *ndr, int ndr_flags, struct winreg_String *r);
void ndr_print_winreg_String(struct ndr_print *ndr, const char *name, const struct winreg_String *r);
void ndr_print_KeySecurityData(struct ndr_print *ndr, const char *name, const struct KeySecurityData *r);
void ndr_print_winreg_SecBuf(struct ndr_print *ndr, const char *name, const struct winreg_SecBuf *r);
void ndr_print_winreg_CreateAction(struct ndr_print *ndr, const char *name, enum winreg_CreateAction r);
void ndr_print_winreg_StringBuf(struct ndr_print *ndr, const char *name, const struct winreg_StringBuf *r);
void ndr_print_winreg_ValNameBuf(struct ndr_print *ndr, const char *name, const struct winreg_ValNameBuf *r);
enum ndr_err_code ndr_push_winreg_NotifyChangeType(struct ndr_push *ndr, int ndr_flags, uint32_t r);
enum ndr_err_code ndr_pull_winreg_NotifyChangeType(struct ndr_pull *ndr, int ndr_flags, uint32_t *r);
void ndr_print_winreg_NotifyChangeType(struct ndr_print *ndr, const char *name, uint32_t r);
void ndr_print_KeySecurityAttribute(struct ndr_print *ndr, const char *name, const struct KeySecurityAttribute *r);
void ndr_print_QueryMultipleValue(struct ndr_print *ndr, const char *name, const struct QueryMultipleValue *r);
void ndr_print_winreg_OpenHKCR(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKCR *r);
void ndr_print_winreg_OpenHKCU(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKCU *r);
enum ndr_err_code ndr_push_winreg_OpenHKLM(struct ndr_push *ndr, int flags, const struct winreg_OpenHKLM *r);
enum ndr_err_code ndr_pull_winreg_OpenHKLM(struct ndr_pull *ndr, int flags, struct winreg_OpenHKLM *r);
void ndr_print_winreg_OpenHKLM(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKLM *r);
void ndr_print_winreg_OpenHKPD(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKPD *r);
void ndr_print_winreg_OpenHKU(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKU *r);
enum ndr_err_code ndr_push_winreg_CloseKey(struct ndr_push *ndr, int flags, const struct winreg_CloseKey *r);
enum ndr_err_code ndr_pull_winreg_CloseKey(struct ndr_pull *ndr, int flags, struct winreg_CloseKey *r);
void ndr_print_winreg_CloseKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_CloseKey *r);
enum ndr_err_code ndr_push_winreg_CreateKey(struct ndr_push *ndr, int flags, const struct winreg_CreateKey *r);
enum ndr_err_code ndr_pull_winreg_CreateKey(struct ndr_pull *ndr, int flags, struct winreg_CreateKey *r);
void ndr_print_winreg_CreateKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_CreateKey *r);
enum ndr_err_code ndr_push_winreg_DeleteKey(struct ndr_push *ndr, int flags, const struct winreg_DeleteKey *r);
enum ndr_err_code ndr_pull_winreg_DeleteKey(struct ndr_pull *ndr, int flags, struct winreg_DeleteKey *r);
void ndr_print_winreg_DeleteKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_DeleteKey *r);
void ndr_print_winreg_DeleteValue(struct ndr_print *ndr, const char *name, int flags, const struct winreg_DeleteValue *r);
enum ndr_err_code ndr_push_winreg_EnumKey(struct ndr_push *ndr, int flags, const struct winreg_EnumKey *r);
enum ndr_err_code ndr_pull_winreg_EnumKey(struct ndr_pull *ndr, int flags, struct winreg_EnumKey *r);
void ndr_print_winreg_EnumKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_EnumKey *r);
enum ndr_err_code ndr_push_winreg_EnumValue(struct ndr_push *ndr, int flags, const struct winreg_EnumValue *r);
enum ndr_err_code ndr_pull_winreg_EnumValue(struct ndr_pull *ndr, int flags, struct winreg_EnumValue *r);
void ndr_print_winreg_EnumValue(struct ndr_print *ndr, const char *name, int flags, const struct winreg_EnumValue *r);
enum ndr_err_code ndr_push_winreg_FlushKey(struct ndr_push *ndr, int flags, const struct winreg_FlushKey *r);
enum ndr_err_code ndr_pull_winreg_FlushKey(struct ndr_pull *ndr, int flags, struct winreg_FlushKey *r);
void ndr_print_winreg_FlushKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_FlushKey *r);
enum ndr_err_code ndr_push_winreg_GetKeySecurity(struct ndr_push *ndr, int flags, const struct winreg_GetKeySecurity *r);
enum ndr_err_code ndr_pull_winreg_GetKeySecurity(struct ndr_pull *ndr, int flags, struct winreg_GetKeySecurity *r);
void ndr_print_winreg_GetKeySecurity(struct ndr_print *ndr, const char *name, int flags, const struct winreg_GetKeySecurity *r);
void ndr_print_winreg_LoadKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_LoadKey *r);
enum ndr_err_code ndr_push_winreg_NotifyChangeKeyValue(struct ndr_push *ndr, int flags, const struct winreg_NotifyChangeKeyValue *r);
enum ndr_err_code ndr_pull_winreg_NotifyChangeKeyValue(struct ndr_pull *ndr, int flags, struct winreg_NotifyChangeKeyValue *r);
void ndr_print_winreg_NotifyChangeKeyValue(struct ndr_print *ndr, const char *name, int flags, const struct winreg_NotifyChangeKeyValue *r);
enum ndr_err_code ndr_push_winreg_OpenKey(struct ndr_push *ndr, int flags, const struct winreg_OpenKey *r);
enum ndr_err_code ndr_pull_winreg_OpenKey(struct ndr_pull *ndr, int flags, struct winreg_OpenKey *r);
void ndr_print_winreg_OpenKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenKey *r);
enum ndr_err_code ndr_push_winreg_QueryInfoKey(struct ndr_push *ndr, int flags, const struct winreg_QueryInfoKey *r);
enum ndr_err_code ndr_pull_winreg_QueryInfoKey(struct ndr_pull *ndr, int flags, struct winreg_QueryInfoKey *r);
void ndr_print_winreg_QueryInfoKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_QueryInfoKey *r);
enum ndr_err_code ndr_push_winreg_QueryValue(struct ndr_push *ndr, int flags, const struct winreg_QueryValue *r);
enum ndr_err_code ndr_pull_winreg_QueryValue(struct ndr_pull *ndr, int flags, struct winreg_QueryValue *r);
void ndr_print_winreg_QueryValue(struct ndr_print *ndr, const char *name, int flags, const struct winreg_QueryValue *r);
void ndr_print_winreg_ReplaceKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_ReplaceKey *r);
void ndr_print_winreg_RestoreKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_RestoreKey *r);
void ndr_print_winreg_SaveKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_SaveKey *r);
void ndr_print_winreg_SetKeySecurity(struct ndr_print *ndr, const char *name, int flags, const struct winreg_SetKeySecurity *r);
void ndr_print_winreg_SetValue(struct ndr_print *ndr, const char *name, int flags, const struct winreg_SetValue *r);
void ndr_print_winreg_UnLoadKey(struct ndr_print *ndr, const char *name, int flags, const struct winreg_UnLoadKey *r);
void ndr_print_winreg_InitiateSystemShutdown(struct ndr_print *ndr, const char *name, int flags, const struct winreg_InitiateSystemShutdown *r);
void ndr_print_winreg_AbortSystemShutdown(struct ndr_print *ndr, const char *name, int flags, const struct winreg_AbortSystemShutdown *r);
enum ndr_err_code ndr_push_winreg_GetVersion(struct ndr_push *ndr, int flags, const struct winreg_GetVersion *r);
enum ndr_err_code ndr_pull_winreg_GetVersion(struct ndr_pull *ndr, int flags, struct winreg_GetVersion *r);
void ndr_print_winreg_GetVersion(struct ndr_print *ndr, const char *name, int flags, const struct winreg_GetVersion *r);
void ndr_print_winreg_OpenHKCC(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKCC *r);
void ndr_print_winreg_OpenHKDD(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKDD *r);
enum ndr_err_code ndr_push_winreg_QueryMultipleValues(struct ndr_push *ndr, int flags, const struct winreg_QueryMultipleValues *r);
enum ndr_err_code ndr_pull_winreg_QueryMultipleValues(struct ndr_pull *ndr, int flags, struct winreg_QueryMultipleValues *r);
void ndr_print_winreg_QueryMultipleValues(struct ndr_print *ndr, const char *name, int flags, const struct winreg_QueryMultipleValues *r);
void ndr_print_winreg_InitiateSystemShutdownEx(struct ndr_print *ndr, const char *name, int flags, const struct winreg_InitiateSystemShutdownEx *r);
void ndr_print_winreg_SaveKeyEx(struct ndr_print *ndr, const char *name, int flags, const struct winreg_SaveKeyEx *r);
void ndr_print_winreg_OpenHKPT(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKPT *r);
void ndr_print_winreg_OpenHKPN(struct ndr_print *ndr, const char *name, int flags, const struct winreg_OpenHKPN *r);
void ndr_print_winreg_QueryMultipleValues2(struct ndr_print *ndr, const char *name, int flags, const struct winreg_QueryMultipleValues2 *r);
#endif /* _HEADER_NDR_winreg */
