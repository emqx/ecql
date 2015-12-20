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
%%% @author Feng Lee <feng@emqtt.io>
%%%
%%% @doc CQL Frame:
%%%
%%% 0         8        16        24        32         40
%%% +---------+---------+---------+---------+---------+
%%% | version |  flags  |      stream       | opcode  |
%%% +---------+---------+---------+---------+---------+
%%% |                length                 |
%%% +---------+---------+---------+---------+
%%% |                                       |
%%% .            ...  body ...              .
%%% .                                       .
%%% .                                       .
%%% +----------------------------------------
%%%
%%% @end
%%%-----------------------------------------------------------------------------
-module(ecql_frame).

-include("ecql.hrl").

-include("ecql_frame.hrl").

-export([parser/0, serialize/1]).

-ifdef(TEST).
-compile(export_all).
-endif.

%% @doc Initialize a parser
parser() ->
    fun(Bin) -> parse(Bin, none) end.

%% @doc Parse Frame
parse(<<>>, none) ->
    {more, fun(Bin) -> parse(Bin, none) end};

parse(Bin, none) when size(Bin) < ?HEADER_SIZE ->
    {more, fun(More) -> parse(<<Bin/binary, More/binary>>, none) end};

parse(<<?VER_RESP:8, Flags:8, Stream:16, OpCode:8, Length:32, Bin/binary>>, none) ->
    parse_body(Bin, #cql_frame{version = ?VER_RESP, flags = Flags,
                               stream = Stream, opcode = OpCode,
                               length = Length});

parse(Bin, Cont) -> Cont(Bin).

parse_body(Bin, Frame = #cql_frame{length = 0}) ->
    {ok, Frame, Bin};

parse_body(Bin, Frame = #cql_frame{length = Len}) when size(Bin) < Len ->
    {more, fun(More) -> parse_body(<<Bin/binary, More/binary>>, Frame) end};

parse_body(Bin, Frame = #cql_frame{length = Len}) ->
    <<Body:Len/binary, Rest/binary>> = Bin,
    Resp = parse_resp(Frame#cql_frame{body = Body}), 
    {ok, Frame#cql_frame{resp = Resp}, Rest}.

parse_resp(#cql_frame{opcode = ?OPCODE_ERROR, body = Body}) ->
    <<Code:?int, Rest/binary>> = Body,
    {Message, Rest1} = parse_string(Rest),
    #cql_error{code = Code, message = Message};

parse_resp(#cql_frame{opcode = ?OPCODE_READY}) ->
    #cql_ready_resp{};

parse_resp(#cql_frame{opcode = ?OPCODE_AUTHENTICATE, body = Body}) ->
    {ClassName, Rest} = parse_string(Body),
    #cql_authenticate_resp{class_name = ClassName};

parse_resp(#cql_frame{opcode = ?OPCODE_SUPPORTED, body = Body}) ->
    {Multimap, _Rest} =  parse_string_multimap(Body),
    #cql_supported_resp{options = Multimap};

parse_resp(#cql_frame{opcode = ?OPCODE_RESULT, body = Body}) ->
    <<Kind:?int, Bin/binary>> = Body,
    parse_result(Bin, #cql_result_resp{kind = result_kind(Kind)});

parse_resp(#cql_frame{opcode = ?OPCODE_EVENT, body = Body}) ->
    %%TODO:...
    {EventType, Rest} = parse_string(Body),
    #cql_event{type = EventType};
    
parse_resp(#cql_frame{opcode = ?OPCODE_AUTH_CHALLENGE, body = Body}) ->
    {Token, _Rest} = parse_bytes(Body),
    #cql_auth_challenge{token = Token};

parse_resp(#cql_frame{opcode = ?OPCODE_AUTH_SUCCESS, body = <<>>}) ->
    #cql_auth_success{token = <<>>};

parse_resp(#cql_frame{opcode = ?OPCODE_AUTH_SUCCESS, body = Body}) ->
    {Token, _Rest} = parse_bytes(Body),
    #cql_auth_success{token = Token}.

parse_result(_Bin, Resp = #cql_result_resp{kind = void}) ->
    Resp;
parse_result(Bin, Resp = #cql_result_resp{kind = rows}) ->
    %%TODO:
    Resp;
parse_result(Bin, Resp = #cql_result_resp{kind = set_keyspace}) ->
    {Keyspace, _Rest} = parse_string(Bin),
    Resp#cql_result_resp{result = Keyspace};
parse_result(Bin, Resp = #cql_result_resp{kind = prepared}) ->
    %%TODO:
    Resp;
parse_result(Bin, Resp = #cql_result_resp{kind = schema_change}) ->
    %%TODO:
    Resp.

parse_string_multimap(<<Len:?short, Bin/binary>>) ->
    parse_string_multimap(Len, Bin, []).

parse_string_multimap(0, Rest, Acc) ->
    {lists:reverse(Acc), Rest};

parse_string_multimap(Len, Bin, Acc) ->
    {Key, Rest} = parse_string(Bin),
    {StrList, Rest1} = parse_string_list(Rest),
    parse_string_multimap(Len - 1, Rest1, [{Key, StrList} | Acc]).

parse_string_list(<<Len:?short, Bin/binary>>) ->
    parse_string_list(Len, Bin, []).

parse_string_list(0, Rest, Acc) ->
    {lists:reverse(Acc), Rest};

parse_string_list(Len, Bin, Acc) ->
    {Str, Rest} = parse_string(Bin),
    parse_string_list(Len - 1, Rest, [Str|Acc]).

parse_string(<<Len:?short, Str:Len/binary, Rest/binary>>) ->
    {Str, Rest}.

parse_bytes(<<Size:?int, Bin/binary>>) ->
    <<Bytes:Size/binary, Rest/binary>> = Bin,
    {Bytes, Rest}.

serialize(Frame) ->
    serialize(header, serialize(body, Frame)).

serialize(body, Frame = #cql_frame{req = Req}) ->
    Body = serialize_req(Req),
    Frame#cql_frame{length = size(Body), body = Body};
    
serialize(header, #cql_frame{version = Version,
                             flags   = Flags,
                             stream  = Stream,
                             opcode  = OpCode,
                             length  = Length,
                             body    = Body}) ->
    <<Version:8, Flags:8, Stream:16, OpCode:8, Length:32, Body/binary>>.

serialize_req(#cql_startup_req{version = Ver, compression = undefined}) ->
    serialize_string_map([{<<"CQL_VERSION">>, Ver}]);
serialize_req(#cql_startup_req{version = Ver, compression = Comp}) ->
    serialize_string_map([{<<"CQL_VERSION">>, Ver}, {<<"COMPRESSION">>, Comp}]);

serialize_req(#cql_auth_response{token = Token}) ->
    serialize_bytes(Token);

serialize_req(#cql_options_req{}) ->
    <<>>;

serialize_req(#cql_query_req{query = Query, parameters = Parameters}) ->
    << (serialize_long_string(Query))/binary, (serialize_query_parameters(Parameters))/binary >>;

serialize_req(#cql_prepare_req{query = Query}) ->
    serialize_long_string(Query);

serialize_req(#cql_execute_req{id = Id, parameters = Parameters}) ->
    << (serialize_short_bytes(Id))/binary, (serialize_query_parameters(Parameters))/binary >>;

serialize_req(#cql_batch_req{type = Type, queries = Queries,
                             consistency = Consistency,
                             flags = Flags, with_names = WithNames,
                             serial_consistency = SerialConsistency,
                             timestamp = Timestamp}) ->

    QueriesBin = << <<(serialize_batch_query(Query))/binary>> || Query <- Queries >>,

    Flags = <<0:5, (flag(WithNames))/binary, (flag(SerialConsistency)):1,
              (flag(Timestamp)):1, 0:1>>,

    Parameters = [{serialize_consistency, SerialConsistency},
                  {timestamp, Timestamp}],

    ParamtersBin = << <<(serialize_parameter(Name, Val))/binary>> || {Name, Val} <- Parameters >>,

    <<Type:?byte, (length(Queries)):?short, QueriesBin/binary, Consistency:?short, Flags:?byte, ParamtersBin/binary>>;

serialize_req(#cql_register_req{event_types = EventTypes}) ->
    serialize_string_list(EventTypes).

serialize_batch_query(#cql_batch_query{kind = 0, string_or_id = Str, values = Values}) ->
    <<0:?byte, (serialize_long_string(Str))/binary, (serialize_batch_query_values(Values))/binary>>;

serialize_batch_query(#cql_batch_query{kind = 1, string_or_id = Id, values = Values}) ->
    <<0:?byte, (serialize_short_bytes(Id))/binary, (serialize_batch_query_values(Values))/binary>>.

serialize_batch_query_values([]) ->
    <<>>;
serialize_batch_query_values([H|_] = Values) when is_tuple(H) ->
    ValuesBin = << <<(serialize_string(Name))/binary, (serialize_bytes(Val))/binary>> || {Name, Val} <- Values >>,
    << (length(Values)):?short, ValuesBin/binary>>;

serialize_batch_query_values([H|_] = Values) when is_binary(H) ->
    ValuesBin = << <<(serialize_bytes(Val))/binary>> || Val <- Values >>,
    << (length(Values)):?short, ValuesBin/binary>>.
    
serialize_query_parameters(#cql_query_parameters{consistency = Consistency,
                                                 values = Values,
                                                 skip_metadata = SkipMetadata,
                                                 result_page_size = PageSize,
                                                 paging_state = PagingState,
                                                 serial_consistency = SerialConsistency,
                                                 timestamp = Timestamp} = QueryParameters) ->
    Flags = <<0:1, (flag(values, Values)):1, (flag(Timestamp)):1, (flag(SerialConsistency)):1,
              (flag(PagingState)):1, (flag(PageSize)):1, (flag(SkipMetadata)):1, (flag(Values)):1>>,
    [_H|Parameters] = ?record_to_proplist(cql_query_parameters, QueryParameters),

    Bin = << <<(serialize_parameter(Name, Val))/binary>> || {Name, Val} <- Parameters, Val =/= undefined >>,

    <<Consistency:?short, Flags:?byte, Bin/binary>>.

serialize_parameter(values, [H |_] = Vals) when is_tuple(H) ->
    Bin = << <<(serialize_string(Name))/binary, (serialize_bytes(Val))/binary>> || {Name, Val} <- Vals >>,
    <<(length(Vals)):?short, Bin/binary>>;

serialize_parameter(values, [H |_] = Vals) when is_binary(H) ->
    Bin = << <<(serialize_bytes(Val))/binary>> || Val <- Vals >>,
    <<(length(Vals)):?short, Bin/binary>>;

serialize_parameter(result_page_size, PageSize) ->
    <<PageSize:?int>>;

serialize_parameter(paging_state, PagingState) ->
    serialize_bytes(PagingState);

serialize_parameter(serial_consistency, SerialConsistency) ->
    <<SerialConsistency:?short>>;

serialize_parameter(timestamp, Timestamp) ->
    <<Timestamp:?long>>.

serialize_string_multimap(Map) ->
    Bin = << <<(serialize_string(K))/binary, (serialize_string_list(L))/binary>> || {K, L} <- Map >>,
    <<(length(Map)):?short, Bin/binary>>.

serialize_string_map(Map) ->
    << <<(serialize_string(K))/binary, (serialize_string(V))/binary>> || {K, V} <- Map >>.

serialize_string_list(List) ->
    Bin = << <<(serialize_string(S))/binary>> || S <- List >>,
    <<(length(List)):?short, Bin/binary>>.

serialize_string(S) ->
    <<(size(S)):?short, S/binary>>.

serialize_long_string(S) ->
    <<(size(S)):?long, S/binary>>.

serialize_short_bytes(Bytes) ->
    <<(size(Bytes)):?short, Bytes/binary>>.

serialize_bytes(Bytes) ->
    <<(size(Bytes)):?int, Bytes/binary>>.

serialize_option_list(Options) ->
    Bin = << <<(serialize_option(Opt))/binary>> || Opt <- Options >>,
    <<(size(Options)):?short, Bin/binary>>.

serialize_option({Id, Val}) ->
    %%TODO:...
    <<>>.

result_kind(16#01) -> void;
result_kind(16#02) -> rows;
result_kind(16#03) -> set_keyspace;
result_kind(16#04) -> prepared;
result_kind(16#05) -> schema_change;
result_kind(void)  -> 16#01;
result_kind(rows)  -> 16#02;
result_kind(set_keyspace)  -> 16#03;
result_kind(prepared)      -> 16#04;
result_kind(schema_change) -> 16#05.

flag(values, [Val|_]) when is_binary(Val) -> 0;
flag(values, [Val|_]) when is_tuple(Val)  -> 1.

flag(undefined) -> 0;
flag(false)     -> 0;
flag(true)      -> 1;
flag(_Val)      -> 1.

