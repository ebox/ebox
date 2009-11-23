/*
   Unix SMB/CIFS implementation.
   NT Domain Authentication SMB / MSRPC client
   Copyright (C) Andrew Tridgell 1992-2000
   Copyright (C) Jeremy Allison                    1998.
   Largely re-written by Jeremy Allison (C)	   2005.
   Copyright (C) Guenther Deschner                 2008.

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
 Wrapper function that uses the auth and auth2 calls to set up a NETLOGON
 credentials chain. Stores the credentials in the struct dcinfo in the
 netlogon pipe struct.
****************************************************************************/

NTSTATUS rpccli_netlogon_setup_creds(struct rpc_pipe_client *cli,
				     const char *server_name,
				     const char *domain,
				     const char *clnt_name,
				     const char *machine_account,
				     const unsigned char machine_pwd[16],
				     enum netr_SchannelType sec_chan_type,
				     uint32_t *neg_flags_inout)
{
	NTSTATUS result = NT_STATUS_UNSUCCESSFUL;
	struct netr_Credential clnt_chal_send;
	struct netr_Credential srv_chal_recv;
	struct dcinfo *dc;
	bool retried = false;

	SMB_ASSERT(ndr_syntax_id_equal(&cli->abstract_syntax,
				       &ndr_table_netlogon.syntax_id));

	TALLOC_FREE(cli->dc);
	cli->dc = talloc_zero(cli, struct dcinfo);
	if (cli->dc == NULL) {
		return NT_STATUS_NO_MEMORY;
	}
	dc = cli->dc;

	/* Store the machine account password we're going to use. */
	memcpy(dc->mach_pw, machine_pwd, 16);

	fstrcpy(dc->remote_machine, "\\\\");
	fstrcat(dc->remote_machine, server_name);

	fstrcpy(dc->domain, domain);

	fstr_sprintf( dc->mach_acct, "%s$", machine_account);

 again:
	/* Create the client challenge. */
	generate_random_buffer(clnt_chal_send.data, 8);

	/* Get the server challenge. */
	result = rpccli_netr_ServerReqChallenge(cli, talloc_tos(),
						dc->remote_machine,
						clnt_name,
						&clnt_chal_send,
						&srv_chal_recv);
	if (!NT_STATUS_IS_OK(result)) {
		return result;
	}

	/* Calculate the session key and client credentials */
	creds_client_init(*neg_flags_inout,
			dc,
			&clnt_chal_send,
			&srv_chal_recv,
			machine_pwd,
			&clnt_chal_send);

	/*
	 * Send client auth-2 challenge and receive server repy.
	 */

	result = rpccli_netr_ServerAuthenticate2(cli, talloc_tos(),
						 dc->remote_machine,
						 dc->mach_acct,
						 sec_chan_type,
						 clnt_name,
						 &clnt_chal_send, /* input. */
						 &srv_chal_recv, /* output. */
						 neg_flags_inout);

	/* we might be talking to NT4, so let's downgrade in that case and retry
	 * with the returned neg_flags - gd */

	if (NT_STATUS_EQUAL(result, NT_STATUS_ACCESS_DENIED) && !retried) {
		retried = true;
		goto again;
	}

	if (!NT_STATUS_IS_OK(result)) {
		return result;
	}

	/*
	 * Check the returned value using the initial
	 * server received challenge.
	 */

	if (!netlogon_creds_client_check(dc, &srv_chal_recv)) {
		/*
		 * Server replied with bad credential. Fail.
		 */
		DEBUG(0,("rpccli_netlogon_setup_creds: server %s "
			"replied with bad credential\n",
			cli->desthost ));
		return NT_STATUS_ACCESS_DENIED;
	}

	DEBUG(5,("rpccli_netlogon_setup_creds: server %s credential "
		"chain established.\n",
		cli->desthost ));

	return NT_STATUS_OK;
}

/* Logon domain user */

NTSTATUS rpccli_netlogon_sam_logon(struct rpc_pipe_client *cli,
				   TALLOC_CTX *mem_ctx,
				   uint32 logon_parameters,
				   const char *domain,
				   const char *username,
				   const char *password,
				   const char *workstation,
				   int logon_type)
{
	NTSTATUS result = NT_STATUS_UNSUCCESSFUL;
	struct netr_Authenticator clnt_creds;
	struct netr_Authenticator ret_creds;
	union netr_LogonLevel *logon;
	union netr_Validation validation;
	uint8_t authoritative;
	int validation_level = 3;
	fstring clnt_name_slash;
	uint8 zeros[16];

	ZERO_STRUCT(ret_creds);
	ZERO_STRUCT(zeros);

	logon = TALLOC_ZERO_P(mem_ctx, union netr_LogonLevel);
	if (!logon) {
		return NT_STATUS_NO_MEMORY;
	}

	if (workstation) {
		fstr_sprintf( clnt_name_slash, "\\\\%s", workstation );
	} else {
		fstr_sprintf( clnt_name_slash, "\\\\%s", global_myname() );
	}

	/* Initialise input parameters */

	netlogon_creds_client_step(cli->dc, &clnt_creds);

	switch (logon_type) {
	case NetlogonInteractiveInformation: {

		struct netr_PasswordInfo *password_info;

		struct samr_Password lmpassword;
		struct samr_Password ntpassword;

		unsigned char lm_owf_user_pwd[16], nt_owf_user_pwd[16];

		unsigned char lm_owf[16];
		unsigned char nt_owf[16];
		unsigned char key[16];

		password_info = TALLOC_ZERO_P(mem_ctx, struct netr_PasswordInfo);
		if (!password_info) {
			return NT_STATUS_NO_MEMORY;
		}

		nt_lm_owf_gen(password, nt_owf_user_pwd, lm_owf_user_pwd);

#ifdef DEBUG_PASSWORD
		DEBUG(100,("lm cypher:"));
		dump_data(100, lm_owf_user_pwd, 16);

		DEBUG(100,("nt cypher:"));
		dump_data(100, nt_owf_user_pwd, 16);
#endif
		memset(key, 0, 16);
		memcpy(key, cli->dc->sess_key, 8);

		memcpy(lm_owf, lm_owf_user_pwd, 16);
		SamOEMhash(lm_owf, key, 16);
		memcpy(nt_owf, nt_owf_user_pwd, 16);
		SamOEMhash(nt_owf, key, 16);

#ifdef DEBUG_PASSWORD
		DEBUG(100,("encrypt of lm owf password:"));
		dump_data(100, lm_owf, 16);

		DEBUG(100,("encrypt of nt owf password:"));
		dump_data(100, nt_owf, 16);
#endif
		memcpy(lmpassword.hash, lm_owf, 16);
		memcpy(ntpassword.hash, nt_owf, 16);

		init_netr_PasswordInfo(password_info,
				       domain,
				       logon_parameters,
				       0xdead,
				       0xbeef,
				       username,
				       clnt_name_slash,
				       lmpassword,
				       ntpassword);

		logon->password = password_info;

		break;
	}
	case NetlogonNetworkInformation: {
		struct netr_NetworkInfo *network_info;
		uint8 chal[8];
		unsigned char local_lm_response[24];
		unsigned char local_nt_response[24];
		struct netr_ChallengeResponse lm;
		struct netr_ChallengeResponse nt;

		ZERO_STRUCT(lm);
		ZERO_STRUCT(nt);

		network_info = TALLOC_ZERO_P(mem_ctx, struct netr_NetworkInfo);
		if (!network_info) {
			return NT_STATUS_NO_MEMORY;
		}

		generate_random_buffer(chal, 8);

		SMBencrypt(password, chal, local_lm_response);
		SMBNTencrypt(password, chal, local_nt_response);

		lm.length = 24;
		lm.data = local_lm_response;

		nt.length = 24;
		nt.data = local_nt_response;

		init_netr_NetworkInfo(network_info,
				      domain,
				      logon_parameters,
				      0xdead,
				      0xbeef,
				      username,
				      clnt_name_slash,
				      chal,
				      nt,
				      lm);

		logon->network = network_info;

		break;
	}
	default:
		DEBUG(0, ("switch value %d not supported\n",
			logon_type));
		return NT_STATUS_INVALID_INFO_CLASS;
	}

	result = rpccli_netr_LogonSamLogon(cli, mem_ctx,
					   cli->dc->remote_machine,
					   global_myname(),
					   &clnt_creds,
					   &ret_creds,
					   logon_type,
					   logon,
					   validation_level,
					   &validation,
					   &authoritative);

	if (memcmp(zeros, &ret_creds.cred.data, sizeof(ret_creds.cred.data)) != 0) {
		/* Check returned credentials if present. */
		if (!netlogon_creds_client_check(cli->dc, &ret_creds.cred)) {
			DEBUG(0,("rpccli_netlogon_sam_logon: credentials chain check failed\n"));
			return NT_STATUS_ACCESS_DENIED;
		}
	}

	return result;
}


/**
 * Logon domain user with an 'network' SAM logon
 *
 * @param info3 Pointer to a NET_USER_INFO_3 already allocated by the caller.
 **/

NTSTATUS rpccli_netlogon_sam_network_logon(struct rpc_pipe_client *cli,
					   TALLOC_CTX *mem_ctx,
					   uint32 logon_parameters,
					   const char *server,
					   const char *username,
					   const char *domain,
					   const char *workstation,
					   const uint8 chal[8],
					   DATA_BLOB lm_response,
					   DATA_BLOB nt_response,
					   struct netr_SamInfo3 **info3)
{
	NTSTATUS result = NT_STATUS_UNSUCCESSFUL;
	int validation_level = 3;
	const char *workstation_name_slash;
	const char *server_name_slash;
	uint8 zeros[16];
	struct netr_Authenticator clnt_creds;
	struct netr_Authenticator ret_creds;
	union netr_LogonLevel *logon = NULL;
	struct netr_NetworkInfo *network_info;
	uint8_t authoritative;
	union netr_Validation validation;
	struct netr_ChallengeResponse lm;
	struct netr_ChallengeResponse nt;

	*info3 = NULL;

	ZERO_STRUCT(zeros);
	ZERO_STRUCT(ret_creds);

	ZERO_STRUCT(lm);
	ZERO_STRUCT(nt);

	logon = TALLOC_ZERO_P(mem_ctx, union netr_LogonLevel);
	if (!logon) {
		return NT_STATUS_NO_MEMORY;
	}

	network_info = TALLOC_ZERO_P(mem_ctx, struct netr_NetworkInfo);
	if (!network_info) {
		return NT_STATUS_NO_MEMORY;
	}

	netlogon_creds_client_step(cli->dc, &clnt_creds);

	if (server[0] != '\\' && server[1] != '\\') {
		server_name_slash = talloc_asprintf(mem_ctx, "\\\\%s", server);
	} else {
		server_name_slash = server;
	}

	if (workstation[0] != '\\' && workstation[1] != '\\') {
		workstation_name_slash = talloc_asprintf(mem_ctx, "\\\\%s", workstation);
	} else {
		workstation_name_slash = workstation;
	}

	if (!workstation_name_slash || !server_name_slash) {
		DEBUG(0, ("talloc_asprintf failed!\n"));
		return NT_STATUS_NO_MEMORY;
	}

	/* Initialise input parameters */

	lm.data = lm_response.data;
	lm.length = lm_response.length;
	nt.data = nt_response.data;
	nt.length = nt_response.length;

	init_netr_NetworkInfo(network_info,
			      domain,
			      logon_parameters,
			      0xdead,
			      0xbeef,
			      username,
			      workstation_name_slash,
			      (uint8_t *) chal,
			      nt,
			      lm);

	logon->network = network_info;

	/* Marshall data and send request */

	result = rpccli_netr_LogonSamLogon(cli, mem_ctx,
					   server_name_slash,
					   global_myname(),
					   &clnt_creds,
					   &ret_creds,
					   NetlogonNetworkInformation,
					   logon,
					   validation_level,
					   &validation,
					   &authoritative);
	if (!NT_STATUS_IS_OK(result)) {
		return result;
	}

	if (memcmp(zeros, validation.sam3->base.key.key, 16) != 0) {
		SamOEMhash(validation.sam3->base.key.key,
			   cli->dc->sess_key, 16);
	}

	if (memcmp(zeros, validation.sam3->base.LMSessKey.key, 8) != 0) {
		SamOEMhash(validation.sam3->base.LMSessKey.key,
			   cli->dc->sess_key, 8);
	}

	if (memcmp(zeros, ret_creds.cred.data, sizeof(ret_creds.cred.data)) != 0) {
		/* Check returned credentials if present. */
		if (!netlogon_creds_client_check(cli->dc, &ret_creds.cred)) {
			DEBUG(0,("rpccli_netlogon_sam_network_logon: credentials chain check failed\n"));
			return NT_STATUS_ACCESS_DENIED;
		}
	}

	*info3 = validation.sam3;

	return result;
}

NTSTATUS rpccli_netlogon_sam_network_logon_ex(struct rpc_pipe_client *cli,
					      TALLOC_CTX *mem_ctx,
					      uint32 logon_parameters,
					      const char *server,
					      const char *username,
					      const char *domain,
					      const char *workstation,
					      const uint8 chal[8],
					      DATA_BLOB lm_response,
					      DATA_BLOB nt_response,
					      struct netr_SamInfo3 **info3)
{
	NTSTATUS result = NT_STATUS_UNSUCCESSFUL;
	int validation_level = 3;
	const char *workstation_name_slash;
	const char *server_name_slash;
	uint8 zeros[16];
	union netr_LogonLevel *logon = NULL;
	struct netr_NetworkInfo *network_info;
	uint8_t authoritative;
	union netr_Validation validation;
	struct netr_ChallengeResponse lm;
	struct netr_ChallengeResponse nt;
	uint32_t flags = 0;

	*info3 = NULL;

	ZERO_STRUCT(zeros);

	ZERO_STRUCT(lm);
	ZERO_STRUCT(nt);

	logon = TALLOC_ZERO_P(mem_ctx, union netr_LogonLevel);
	if (!logon) {
		return NT_STATUS_NO_MEMORY;
	}

	network_info = TALLOC_ZERO_P(mem_ctx, struct netr_NetworkInfo);
	if (!network_info) {
		return NT_STATUS_NO_MEMORY;
	}

	if (server[0] != '\\' && server[1] != '\\') {
		server_name_slash = talloc_asprintf(mem_ctx, "\\\\%s", server);
	} else {
		server_name_slash = server;
	}

	if (workstation[0] != '\\' && workstation[1] != '\\') {
		workstation_name_slash = talloc_asprintf(mem_ctx, "\\\\%s", workstation);
	} else {
		workstation_name_slash = workstation;
	}

	if (!workstation_name_slash || !server_name_slash) {
		DEBUG(0, ("talloc_asprintf failed!\n"));
		return NT_STATUS_NO_MEMORY;
	}

	/* Initialise input parameters */

	lm.data = lm_response.data;
	lm.length = lm_response.length;
	nt.data = nt_response.data;
	nt.length = nt_response.length;

	init_netr_NetworkInfo(network_info,
			      domain,
			      logon_parameters,
			      0xdead,
			      0xbeef,
			      username,
			      workstation_name_slash,
			      (uint8_t *) chal,
			      nt,
			      lm);

	logon->network = network_info;

        /* Marshall data and send request */

	result = rpccli_netr_LogonSamLogonEx(cli, mem_ctx,
					     server_name_slash,
					     global_myname(),
					     NetlogonNetworkInformation,
					     logon,
					     validation_level,
					     &validation,
					     &authoritative,
					     &flags);
	if (!NT_STATUS_IS_OK(result)) {
		return result;
	}

	if (memcmp(zeros, validation.sam3->base.key.key, 16) != 0) {
		SamOEMhash(validation.sam3->base.key.key,
			   cli->dc->sess_key, 16);
	}

	if (memcmp(zeros, validation.sam3->base.LMSessKey.key, 8) != 0) {
		SamOEMhash(validation.sam3->base.LMSessKey.key,
			   cli->dc->sess_key, 8);
	}

	*info3 = validation.sam3;

	return result;
}

/*********************************************************
 Change the domain password on the PDC.

 Just changes the password betwen the two values specified.

 Caller must have the cli connected to the netlogon pipe
 already.
**********************************************************/

NTSTATUS rpccli_netlogon_set_trust_password(struct rpc_pipe_client *cli,
					    TALLOC_CTX *mem_ctx,
					    const unsigned char orig_trust_passwd_hash[16],
					    const char *new_trust_pwd_cleartext,
					    const unsigned char new_trust_passwd_hash[16],
					    uint32_t sec_channel_type)
{
	NTSTATUS result;
	uint32_t neg_flags = NETLOGON_NEG_AUTH2_ADS_FLAGS;
	struct netr_Authenticator clnt_creds, srv_cred;

	result = rpccli_netlogon_setup_creds(cli,
					     cli->desthost, /* server name */
					     lp_workgroup(), /* domain */
					     global_myname(), /* client name */
					     global_myname(), /* machine account name */
					     orig_trust_passwd_hash,
					     sec_channel_type,
					     &neg_flags);

	if (!NT_STATUS_IS_OK(result)) {
		DEBUG(3,("rpccli_netlogon_set_trust_password: unable to setup creds (%s)!\n",
			 nt_errstr(result)));
		return result;
	}

	netlogon_creds_client_step(cli->dc, &clnt_creds);

	if (neg_flags & NETLOGON_NEG_PASSWORD_SET2) {

		struct netr_CryptPassword new_password;

		init_netr_CryptPassword(new_trust_pwd_cleartext,
					cli->dc->sess_key,
					&new_password);

		result = rpccli_netr_ServerPasswordSet2(cli, mem_ctx,
							cli->dc->remote_machine,
							cli->dc->mach_acct,
							sec_channel_type,
							global_myname(),
							&clnt_creds,
							&srv_cred,
							&new_password);
		if (!NT_STATUS_IS_OK(result)) {
			DEBUG(0,("rpccli_netr_ServerPasswordSet2 failed: %s\n",
				nt_errstr(result)));
			return result;
		}
	} else {

		struct samr_Password new_password;

		des_crypt112_16(new_password.hash,
				new_trust_passwd_hash,
				cli->dc->sess_key, 1);

		result = rpccli_netr_ServerPasswordSet(cli, mem_ctx,
						       cli->dc->remote_machine,
						       cli->dc->mach_acct,
						       sec_channel_type,
						       global_myname(),
						       &clnt_creds,
						       &srv_cred,
						       &new_password);
		if (!NT_STATUS_IS_OK(result)) {
			DEBUG(0,("rpccli_netr_ServerPasswordSet failed: %s\n",
				nt_errstr(result)));
			return result;
		}
	}

	/* Always check returned credentials. */
	if (!netlogon_creds_client_check(cli->dc, &srv_cred.cred)) {
		DEBUG(0,("credentials chain check failed\n"));
		return NT_STATUS_ACCESS_DENIED;
	}

	return result;
}

