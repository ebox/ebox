/* 
   Unix SMB/CIFS implementation.
   SMB parameters and setup
   Copyright (C) Gerald (Jerry) Carter         2005.
   
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

#ifndef _RPC_CLIENT_H
#define _RPC_CLIENT_H

/* autogenerated client stubs */

#include "librpc/gen_ndr/cli_echo.h"
#include "librpc/gen_ndr/cli_lsa.h"
#include "librpc/gen_ndr/cli_svcctl.h"
#include "librpc/gen_ndr/cli_wkssvc.h"
#include "librpc/gen_ndr/cli_eventlog.h"
#include "librpc/gen_ndr/cli_dfs.h"
#include "librpc/gen_ndr/cli_initshutdown.h"
#include "librpc/gen_ndr/cli_winreg.h"
#include "librpc/gen_ndr/cli_srvsvc.h"
#include "librpc/gen_ndr/cli_samr.h"
#include "librpc/gen_ndr/cli_netlogon.h"
#include "librpc/gen_ndr/cli_dssetup.h"
#include "librpc/gen_ndr/cli_ntsvcs.h"
#include "librpc/gen_ndr/cli_epmapper.h"
#include "librpc/gen_ndr/cli_drsuapi.h"
#include "librpc/gen_ndr/cli_spoolss.h"

#define prs_init_empty( _ps_, _ctx_, _io_ ) (void) prs_init((_ps_), 0, (_ctx_), (_io_))

#endif /* _RPC_CLIENT_H */
