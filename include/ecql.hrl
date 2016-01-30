%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015-2016 Feng Lee <feng@emqtt.io>. All Rights Reserved.
%%%
%%% Permission is hereby granted, free of charge, to any person obtaining a copy
%%% of this software and associated documentation files (the "Software"), to deal
%%% in the Software without restriction, including without limitation the rights
%%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%%% copies of the Software, and to permit persons to whom the Software is
%%% furnished to do so, subject to the following conditions:
%%%
%%% The above copyright notice and this permission notice shall be included in all
%%% copies or substantial portions of the Software.
%%%
%%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%%% SOFTWARE.
%%%-----------------------------------------------------------------------------

%%------------------------------------------------------------------------------
%% Version
%%------------------------------------------------------------------------------

-define(ECQL_VER,       <<"3.0.0">>).
-define(VER_REQ,        16#03).
-define(VER_RESP,       16#83).

%%------------------------------------------------------------------------------
%% OpCode
%%------------------------------------------------------------------------------

-define(OP_ERROR,          16#00).
-define(OP_STARTUP,        16#01).
-define(OP_READY,          16#02).
-define(OP_AUTHENTICATE,   16#03).
-define(OP_OPTIONS,        16#05).
-define(OP_SUPPORTED,      16#06). 
-define(OP_QUERY,          16#07).
-define(OP_RESULT,         16#08).
-define(OP_PREPARE,        16#09).
-define(OP_EXECUTE,        16#0A).
-define(OP_REGISTER,       16#0B).
-define(OP_EVENT,          16#0C).
-define(OP_BATCH,          16#0D).
-define(OP_AUTH_CHALLENGE, 16#0E).
-define(OP_AUTH_RESPONSE,  16#0F).
-define(OP_AUTH_SUCCESS,   16#10).

-type opcode() :: ?OP_ERROR..?OP_AUTH_SUCCESS.

%%------------------------------------------------------------------------------
%% [consistency] A consistency level specification.
%% This is a [short] representing a consistency level with the following.
%%------------------------------------------------------------------------------

-define(CL_ANY,          16#00).
-define(CL_ONE,          16#01).
-define(CL_TWO,          16#02).
-define(CL_THREE,        16#03).
-define(CL_QUORUM,       16#04).
-define(CL_ALL,          16#05).
-define(CL_LOCAL_QUORUM, 16#06).
-define(CL_EACH_QUORUM,  16#07).
-define(CL_SERIAL,       16#08).
-define(CL_LOCAL_SERIAL, 16#09).
-define(CL_LOCAL_ONE,    16#0A).

-define(IS_CL(I), (is_atom(I) orelse (?CL_ANY =< I andalso I =< ?CL_LOCAL_ONE))).

-type consistency() :: ?CL_ANY..?CL_LOCAL_ONE.

%%------------------------------------------------------------------------------
%% Error Code
%%------------------------------------------------------------------------------

-define(ERR_SERVER_ERROR,   16#0000).
-define(ERR_PROTOCOL_ERROR, 16#000A).
-define(ERR_BAD_CREDENTIALS,16#0100).
-define(ERR_UNAVAILABE,     16#1000).
-define(ERR_OVLOADED,       16#1001).
-define(ERR_BOOTSTRAPPING,  16#1002).
-define(ERR_TRUNCATE_ERROR, 16#1003).
-define(ERR_WRITE_TIMEOUT,  16#1100).
-define(ERR_READ_TIMEOUT,   16#1200).
-define(ERR_SYNTAX_ERROR,   16#2000).
-define(ERR_UNAUTHORIZED,   16#2100).
-define(ERR_CONFIG_ERRO,    16#2300).
-define(ERR_ALREADY_EXISTS, 16#2400).
-define(ERR_UNPREPARED,     16#2500).

-type ecql_error_code() :: ?ERR_SERVER_ERROR..?ERR_UNPREPARED.

%%------------------------------------------------------------------------------
%% Frame
%%------------------------------------------------------------------------------

-type stream_id() :: 0..16#FFFF.

-record(ecql_frame, {version = ?VER_REQ, flags = 0,
                     stream  :: stream_id(),
                     opcode  :: opcode(),
                     length  :: pos_integer(),
                     body    :: binary(),
                     message}).

-type ecql_frame() :: #ecql_frame{}.

-define(REQ_FRAME(OpCode, Req),
        #ecql_frame{version = ?VER_REQ, opcode = OpCode, message = Req}).

-define(REQ_FRAME(Stream, OpCode, Req),
        #ecql_frame{version = ?VER_REQ, stream = Stream,
                    opcode = OpCode, message = Req}).

-define(RESP_FRAME(OpCode, Resp),
        #ecql_frame{version = ?VER_RESP, opcode = OpCode, message = Resp}).

-define(RESP_FRAME(Stream, OpCode, Resp),
        #ecql_frame{version = ?VER_RESP, stream = Stream,
                    opcode = OpCode, message = Resp}).

-define(ERROR_FRAME(Error),
        #ecql_frame{version = ?VER_RESP, opcode = ?OP_ERROR, message = Error}).

-define(READY_FRAME,
        #ecql_frame{version = ?VER_RESP, opcode = ?OP_READY, message = #ecql_ready{}}).

-define(SUPPORTED_FRAME(Options), #ecql_frame{version = ?VER_RESP, opcode = ?OP_SUPPORTED,
                                              message = #ecql_supported{options = Options}}).

-define(RESULT_FRAME(Kind, Result),
        #ecql_frame{version = ?VER_RESP, opcode = ?OP_RESULT,
                    message = #ecql_result{kind = Kind, data = Result}}).

%%------------------------------------------------------------------------------
%% Request Message
%%------------------------------------------------------------------------------

-record(ecql_startup, {version = ?ECQL_VER,
                       compression :: boolean()}).

-record(ecql_auth_response, {token = <<>>}).

-record(ecql_options, {}).

-record(ecql_query, {query, consistency = ?CL_ONE, flags, values, skip_metadata,
                     result_page_size, paging_state, serial_consistency, timestamp}).

-type ecql_query() :: #ecql_query{}.

-record(ecql_prepare, {query :: binary()}).

-record(ecql_execute, {id :: binary(), query :: ecql_query()}).

-record(ecql_batch_query, {kind, query_or_id, values}).

-record(ecql_batch, {type, queries :: [#ecql_batch_query{}],
                     consistency, flags, with_names :: boolean(),
                     serial_consistency, timestamp}).

-record(ecql_register, {event_types :: [binary()]}).

%%------------------------------------------------------------------------------
%% Response Message
%%------------------------------------------------------------------------------

-record(ecql_error, {code    :: ecql_error_code(),
                     message :: binary(),
                     detail  :: any()}).

-record(ecql_ready, {}).

-record(ecql_authenticate, {class}).

-record(ecql_supported, {options}).

-type ecql_result_kind() :: void | rows | set_keyspace | prepared | schema_change.

-record(ecql_rows_meta, {count, columns, paging_state, table_spec}).

-record(ecql_rows, {meta :: #ecql_rows_meta{}, data :: list()}).

-record(ecql_set_keyspace, {keyspace}).

-record(ecql_prepared, {id, metadata, result_metadata}).

-record(ecql_schema_change, {type, target, options}).

-record(ecql_result, {kind :: ecql_result_kind(),
                      data :: #ecql_rows{} | #ecql_set_keyspace{}
                            | #ecql_prepared{} | #ecql_schema_change{}}).

-record(ecql_event, {type :: binary(), data :: binary()}).

-record(ecql_auth_challenge, {token :: binary()}).

-record(ecql_auth_success, {token :: binary()}).

