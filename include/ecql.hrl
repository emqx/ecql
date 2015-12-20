%%%-----------------------------------------------------------------------------
%%% Copyright (c) 2015 eMQTT.IO, All Rights Reserved.
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

-define(HEADER_SIZE,    9).

-define(VER_REQ,        16#03).
-define(VER_RESP,       16#83).

-define(OPCODE_ERROR,          16#00).
-define(OPCODE_STARTUP,        16#01).
-define(OPCODE_READY,          16#02).
-define(OPCODE_AUTHENTICATE,   16#03).
-define(OPCODE_OPTIONS,        16#05).
-define(OPCODE_SUPPORTED,      16#06). 
-define(OPCODE_QUERY,          16#07).
-define(OPCODE_RESULT,         16#08).
-define(OPCODE_PREPARE,        16#09).
-define(OPCODE_EXECUTE,        16#0A).
-define(OPCODE_REGISTER,       16#0B).
-define(OPCODE_EVENT,          16#0C).
-define(OPCODE_BATCH,          16#0D).
-define(OPCODE_AUTH_CHALLENGE, 16#0E).
-define(OPCODE_AUTH_RESPONSE,  16#0F).
-define(OPCODE_AUTH_SUCCESS,   16#10).

-type opcode() :: ?OPCODE_ERROR..?OPCODE_AUTH_SUCCESS.

-define(record_to_proplist(Def, Rec),
        lists:zip(record_info(fields, Def),
                  tl(tuple_to_list(Rec)))).

-define(record_to_proplist(Def, Rec, Fields),
    [{K, V} || {K, V} <- ?record_to_proplist(Def, Rec),
                         lists:member(K, Fields)]).

-record(cql_frame, {version = ?VER_REQ, flags, stream, opcode, length, body, req, resp}).

%% Requests from Client -> Cassandra
-record(cql_startup_req, {version = <<"3.0.0">>, compression}).

-record(cql_auth_response, {token = <<>>}).

-record(cql_options_req, {}).

-record(cql_query_parameters, {consistency, flags, values, skip_metadata,
                               result_page_size, paging_state, serial_consistency,
                               timestamp}).

-record(cql_query_req, {query, parameters :: #cql_query_parameters{}}).

-record(cql_prepare_req, {query}).

-record(cql_execute_req, {id, parameters}).

-record(cql_batch_query, {kind, string_or_id, values}).

-record(cql_batch_req, {type, queries :: [#cql_batch_query{}],
                        consistency, flags, with_names :: boolean(),
                        serial_consistency, timestamp}).

-record(cql_register_req, {event_types :: list(string())}).

%% Response from Cassandra -> Client

-record(cql_error, {code, message}).

-record(cql_ready_resp, {}).

-record(cql_authenticate_resp, {class_name}).

-record(cql_supported_resp, {options}).

-type cql_result_kind() :: void | rows | set_keyspace | prepared | schema_change.

-record(cql_result_rows, {metadata, rows_count, rows_content}).

-record(cql_result_schema_change, {change_type, target, options}).

-record(cql_result_prepared, {id, metadata, result_metadata}).

-record(cql_result_resp, {kind :: cql_result_kind(), result}).

-record(cql_event, {type}).

-record(cql_auth_challenge, {token}).

-record(cql_auth_success, {token}).


