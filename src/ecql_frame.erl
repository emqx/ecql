%%-----------------------------------------------------------------------------
%% Copyright (c) 2015 Feng Lee <feng@emqtt.io>. All Rights Reserved.
%%
%% Permission is hereby granted, free of charge, to any person obtaining a copy
%% of this software and associated documentation files (the "Software"), to deal
%% in the Software without restriction, including without limitation the rights
%% to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
%% copies of the Software, and to permit persons to whom the Software is
%% furnished to do so, subject to the following conditions:
%%
%% The above copyright notice and this permission notice shall be included in all
%% copies or substantial portions of the Software.
%%
%% THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
%% IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
%% FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
%% AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
%% LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
%% OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
%% SOFTWARE.

%%-----------------------------------------------------------------------------
%% @author Feng Lee <feng@emqtt.io>
%%
%% @doc CQL Frame:
%%
%% 0         8        16        24        32         40
%% +---------+---------+---------+---------+---------+
%% | version |  flags  |      stream       | opcode  |
%% +---------+---------+---------+---------+---------+
%% |                length                 |
%% +---------+---------+---------+---------+
%% |                                       |
%% .            ...  body ...              .
%% .                                       .
%% .                                       .
%% +----------------------------------------
%%
%% @end
%%-----------------------------------------------------------------------------

-module(ecql_frame).

-include("ecql.hrl").

-include("ecql_types.hrl").

-export([parser/0, serialize/1]).

-export([stream/1]).

-ifdef(TEST).
-compile(export_all).
-endif.

-define(record_to_proplist(Def, Rec),
        lists:zip(record_info(fields, Def),
                  tl(tuple_to_list(Rec)))).

-define(HEADER_SIZE, 9).

-define(NULL, -1).

-spec stream(ecql_frame()) -> stream_id().
stream(#ecql_frame{stream = StreamId}) ->
    StreamId.

%% @doc Initialize a parser
parser() ->
    fun(Bin) -> parse(Bin, none) end.

%% @doc Parse Frame
parse(<<>>, none) ->
    {more, fun(Bin) -> parse(Bin, none) end};

parse(Bin, none) when size(Bin) < ?HEADER_SIZE ->
    {more, fun(More) -> parse(<<Bin/binary, More/binary>>, none) end};

parse(<<?VER_RESP:?byte, Flags:?byte, Stream:?short, OpCode:?byte, Length:32/big-integer, Bin/binary>>, none) ->
    parse_body(Bin, #ecql_frame{version = ?VER_RESP, flags = Flags,
                                stream = Stream, opcode = OpCode,
                                length = Length});

parse(Bin, Cont) ->
    Cont(Bin).

parse_body(Bin, Frame = #ecql_frame{length = Len}) when size(Bin) < Len ->
    {more, fun(More) -> parse_body(<<Bin/binary, More/binary>>, Frame) end};

parse_body(Bin, Frame = #ecql_frame{length = Len}) ->
    <<Body:Len/binary, Rest/binary>> = Bin,
    Resp = parse_resp(Frame#ecql_frame{body = Body}),
    {ok, Frame#ecql_frame{message = Resp}, Rest}.

parse_resp(#ecql_frame{opcode = ?OP_ERROR, body = Body}) ->
    <<Code:?int, Rest/binary>> = Body,
    {Message, Rest1} = parse_string(Rest),
    parse_error(#ecql_error{code = Code, message = Message}, Rest1);

parse_resp(#ecql_frame{opcode = ?OP_READY}) ->
    #ecql_ready{};

parse_resp(#ecql_frame{opcode = ?OP_AUTHENTICATE, body = Body}) ->
    {ClassName, _Rest} = parse_string(Body),
    #ecql_authenticate{class = ClassName};

parse_resp(#ecql_frame{opcode = ?OP_SUPPORTED, body = Body}) ->
    {Multimap, _Rest} =  parse_string_multimap(Body),
    #ecql_supported{options = Multimap};

parse_resp(#ecql_frame{opcode = ?OP_RESULT, body = Body}) ->
    <<Kind:?int, Bin/binary>> = Body,
    parse_result(Bin, #ecql_result{kind = result_kind(Kind)});

parse_resp(#ecql_frame{opcode = ?OP_EVENT, body = Body}) ->
    {EventType, Rest} = parse_string(Body),
    {EventData, _Rest} = parse_event(EventType, Rest),
    #ecql_event{type = EventType, data = EventData};

parse_resp(#ecql_frame{opcode = ?OP_AUTH_CHALLENGE, body = Body}) ->
    {Token, _Rest} = parse_bytes(Body),
    #ecql_auth_challenge{token = Token};

parse_resp(#ecql_frame{opcode = ?OP_AUTH_SUCCESS, body = Body}) ->
    {Token, _Rest} = parse_bytes(Body),
    #ecql_auth_success{token = Token}.

parse_error(Error = #ecql_error{code = ?ERR_UNAVAILABE}, Bin) ->
    <<Cl:?short, Required:?int, Alive:?int, _/binary>> = Bin,
    Error#ecql_error{detail = [{consistency, ecql_cl:name(Cl)},
                               {required, Required},
                               {alive, Alive}]};

parse_error(Error = #ecql_error{code = ?ERR_WRITE_TIMEOUT}, Bin) ->
    <<Cl:?short, Received:?int, BlockFor:?int, Rest/binary>> = Bin,
    {WriteType, _} = parse_string(Rest),
    Error#ecql_error{detail = [{consistency, ecql_cl:name(Cl)},
                               {received, Received},
                               {blockfor, BlockFor},
                               {write_type, WriteType}]};

parse_error(Error = #ecql_error{code = ?ERR_READ_TIMEOUT}, Bin) ->
    <<Cl:?short, Received:?int, BlockFor:?int, Present:8, _Rest/binary>> = Bin,
    Error#ecql_error{detail = [{consistency, ecql_cl:name(Cl)},
                               {received, Received},
                               {blockfor, BlockFor},
                               {data_present, Present}]};

parse_error(Error = #ecql_error{code = ?ERR_ALREADY_EXISTS}, Bin) ->
    {Ks, Rest} = parse_string(Bin),
    {Table, _} = parse_string(Rest),
    Error#ecql_error{detail = [{ks, Ks}, {table, Table}]};

parse_error(Error = #ecql_error{code = ?ERR_UNPREPARED}, Bin) ->
    {Id, _} = parse_short_bytes(Bin),
    Error#ecql_error{detail = Id};

parse_error(Error, Bin) -> %% default
    Error#ecql_error{detail = Bin}.

parse_event(EvenType, Bin) when EvenType =:= <<"TOPOLOGY_CHANGE">>;
                                EvenType =:= <<"STATUS_CHANGE">> ->
    {Change, Rest} = parse_string(Bin),
    {IpBytes, Rest2} = parse_bytes(Rest),
    {Ip, _} = ecql_types:decode(inet, size(IpBytes), IpBytes),
    {{Change, Ip}, Rest2};

parse_event(<<"SCHEMA_CHANGE">>, Bin) ->
    {ChangeType, Rest} = parse_string(Bin),
    {Target, Rest1} = parse_string(Rest),
    {Keyspace, Name, RestX} =
    if Target == <<"KEYSPACE">> ->
        {Ks, Rest2} = parse_string(Rest1),
        {Ks, undefined, Rest2};
       Target == <<"TABLE">> orelse Target == <<"TYPE">> ->
        {Ks, Rest2} = parse_string(Rest1),
        {N, Rest3} = parse_string(Rest2),
        {Ks, N, Rest3};
       true ->
        {Rest1, <<>>}
    end,
    {{ChangeType, Target, Keyspace, Name}, RestX};

parse_event(_EventType, Rest) ->
    {Rest, <<>>}.

parse_result(_Bin, Resp = #ecql_result{kind = void}) ->
    Resp;
parse_result(Bin, Resp = #ecql_result{kind = rows}) ->
    {Meta, Rest}   = parse_rows_meta(Bin),
    {Rows, _Rest1} = parse_rows_content(Meta, Rest),
    Resp#ecql_result{data = #ecql_rows{meta = Meta, data = Rows}};
parse_result(Bin, Resp = #ecql_result{kind = set_keyspace}) ->
    {Keyspace, _Rest} = parse_string(Bin),
    Result = #ecql_set_keyspace{keyspace = Keyspace},
    Resp#ecql_result{data = Result};
parse_result(Bin, Resp = #ecql_result{kind = prepared}) ->
    {Id, _Rest} = parse_short_bytes(Bin),
    Resp#ecql_result{data = #ecql_prepared{id = Id}};

parse_result(Bin, Resp = #ecql_result{kind = schema_change}) ->
    Resp#ecql_result{data = parse_schema_change(Bin)}.

parse_schema_change(Bin) ->
    {Type,    Rest}  = parse_string(Bin),
    {Target,  Rest1} = parse_string(Rest),
    {Options, _}     = parse_string(Rest1),
    #ecql_schema_change{type = Type, target = Target, options = Options}.

parse_rows_meta(<<Flags:4/binary, Count:?int, Bin/binary>>) ->
    <<_Unused:29, NoMetadata:1, HashMorePages:1, GlobalTabSpec:1>> = Flags,
    {PagingState, Rest} = parse_paging_state(bool(HashMorePages), Bin),
    {TableSpec, Rest1} = parse_global_table_spec(bool(GlobalTabSpec), Rest),
    {Columns, Rest2} = parse_columns(bool(NoMetadata), bool(GlobalTabSpec), Count, Rest1),
    {#ecql_rows_meta{count = Count, columns = Columns, paging_state = PagingState, table_spec = TableSpec}, Rest2}.

parse_paging_state(false, Bin) ->
    {undefined, Bin};
parse_paging_state(true, Bin) ->
    parse_bytes(Bin).

parse_global_table_spec(false, Bin) ->
    {undefined, Bin};
parse_global_table_spec(true, Bin) ->
    {Keyspace, Rest} = parse_string(Bin),
    {Table, Rest1} = parse_string(Rest),
    {<<Keyspace/binary, ".", Table/binary>>, Rest1}.

parse_columns(true, _GlobalTabSpec, _Count, Bin) ->
    {[], Bin};
parse_columns(false, _GlobalTabSpec, 0, Bin) ->
    {[], Bin};
parse_columns(false, GlobalTabSpec, Count, Bin) ->
    parse_column(GlobalTabSpec, Count, Bin).

parse_column(GlobalTabSpec, Count, Bin) ->
    parse_column(GlobalTabSpec, Count, Bin, []).

parse_column(_GlobalTabSpec, 0, Bin, Acc) ->
    {lists:reverse(Acc), Bin};
parse_column(true, N, Bin, Acc) ->
    {Column, Rest} = parse_string(Bin),
    {Type, Rest1} = parse_type(Rest), 
    parse_column(true, N - 1, Rest1, [{Column, Type}|Acc]);
    
parse_column(false, N, Bin, Acc) ->
    {_Keyspace, Rest} = parse_string(Bin),
    {_Table, Rest1} = parse_string(Rest),
    {Column, Rest2} = parse_string(Rest1),
    {Type, Rest3} = parse_type(Rest2),
    parse_column(false, N - 1, Rest3, [{Column, Type}|Acc]).

parse_type(<<?TYPE_CUSTOM:?short, Bin/binary>>) ->
    {Class, Rest} = parse_string(Bin),
    {{custom, Class}, Rest};
parse_type(<<?TYPE_ASCII:?short, Bin/binary>>) ->
    {ascii, Bin};
parse_type(<<?TYPE_BIGINT:?short, Bin/binary>>) ->
    {bigint, Bin};
parse_type(<<?TYPE_BLOB:?short, Bin/binary>>) ->
    {blob, Bin};
parse_type(<<?TYPE_BOOLEAN:?short, Bin/binary>>) ->
    {boolean, Bin};
parse_type(<<?TYPE_COUNTER:?short, Bin/binary>>) ->
    {counter, Bin};
parse_type(<<?TYPE_DECIMAL:?short, Bin/binary>>) ->
    {decimal, Bin};
parse_type(<<?TYPE_DOUBLE:?short, Bin/binary>>) ->
    {double, Bin};
parse_type(<<?TYPE_FLOAT:?short, Bin/binary>>) ->
    {float, Bin};
parse_type(<<?TYPE_INT:?short, Bin/binary>>) ->
    {int, Bin};
parse_type(<<?TYPE_TIMESTAMP:?short, Bin/binary>>) ->
    {timestamp, Bin};
parse_type(<<?TYPE_UUID:?short, Bin/binary>>) ->
    {uuid, Bin};
parse_type(<<?TYPE_VARCHAR:?short, Bin/binary>>) ->
    {varchar, Bin};
parse_type(<<?TYPE_VARINT:?short, Bin/binary>>) ->
    {varint, Bin};
parse_type(<<?TYPE_TIMEUUID:?short, Bin/binary>>) ->
    {timeuuid, Bin};
parse_type(<<?TYPE_INET:?short, Bin/binary>>) ->
    {inet, Bin};
parse_type(<<?TYPE_LIST:?short, Bin/binary>>) ->
    {Type, Rest} = parse_type(Bin),
    {{list, Type}, Rest};
parse_type(<<?TYPE_MAP:?short, Bin/binary>>) ->
    {KeyType, Rest} = parse_type(Bin),
    {ValType, Rest1} = parse_type(Rest),
    {{map, {KeyType, ValType}}, Rest1};
parse_type(<<?TYPE_SET:?short, Bin/binary>>) ->
    {Type, Rest} = parse_type(Bin),
    {{set, Type}, Rest};
parse_type(<<?TYPE_UDT:?short, _Bin/binary>>) ->
    throw({error, unsupport_udt_type});
parse_type(<<?TYPE_TUPLE:?short, Bin/binary>>) ->
    <<N:?short, Rest/binary>> = Bin,
    {Rest1, ElTypes} =
    lists:foldl(fun(_I, {Rest1, Acc}) ->
            {Type, Rest2} = parse_type(Rest1),
            {Rest2, [Type | Acc]}
        end, {Rest, []}, lists:seq(1, N)),
    {{tuple, list_to_tuple(lists:reverse(ElTypes))}, Rest1}.

parse_rows_content(Meta, <<Count:?int, Bin/binary>>) ->
    parse_rows_content(Meta, Count, Bin).

parse_rows_content(Meta, Count, Bin) ->
    parse_row(Meta, Count, Bin, []).

parse_row(_Meta, 0, Bin, Rows) ->
    {lists:reverse(Rows), Bin};

parse_row(Meta, Count, Bin, Rows) ->
    {Row, Rest} = parse_row(Meta, Bin),
    parse_row(Meta, Count - 1, Rest, [Row|Rows]).

parse_row(#ecql_rows_meta{columns = Columns}, Bin) ->
    {Cells, Rest} = lists:foldl(fun(Col, {CellAcc, LeftBin}) ->
                    {Cell, LeftBin1} = parse_cell(Col, LeftBin),
                    {[Cell | CellAcc], LeftBin1}
            end, {[], Bin}, Columns),
    {lists:reverse(Cells), Rest}.

parse_cell(_Col, <<?NULL:?int, Bin/binary>>) ->
    {null, Bin};
parse_cell({_Name, Type}, Bin) ->
    {Bytes, Rest} = parse_bytes(Bin),
    {Val, _}= ecql_types:decode(Type, size(Bytes), Bytes),
    {Val, Rest}.

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

parse_bytes(<<?NULL:?int, Bin/binary>>) ->
    {<<>>, Bin};
parse_bytes(<<Size:?int, Bin/binary>>) ->
    <<Bytes:Size/binary, Rest/binary>> = Bin,
    {Bytes, Rest}.

parse_short_bytes(<<Size:?short, Bin/binary>>) ->
    <<Bytes:Size/binary, Rest/binary>> = Bin,
    {Bytes, Rest}.

-spec serialize(ecql_frame()) -> binary().
serialize(Frame) ->
    serialize(header, serialize(body, Frame)).

serialize(body, Frame = #ecql_frame{message = Req}) ->
    Body = serialize_req(Req),
    Frame#ecql_frame{length = size(Body), body = Body};
    
serialize(header, #ecql_frame{version = Version,
                              flags   = Flags,
                              stream  = Stream,
                              opcode  = OpCode,
                              length  = Length,
                              body    = Body}) ->
    <<Version:?byte, Flags:?byte, Stream:?short, OpCode:?byte, Length:32/big-integer, Body/binary>>.

serialize_req(#ecql_startup{version = Ver, compression = undefined}) ->
    serialize_string_map([{<<"CQL_VERSION">>, Ver}]);
serialize_req(#ecql_startup{version = Ver, compression = Comp}) ->
    serialize_string_map([{<<"CQL_VERSION">>, Ver}, {<<"COMPRESSION">>, Comp}]);

serialize_req(#ecql_auth_response{token = Token}) ->
    serialize_bytes(Token);

serialize_req(#ecql_options{}) ->
    <<>>;

serialize_req(Query = #ecql_query{query = CQL}) ->
    << (serialize_long_string(CQL))/binary, (serialize_query_parameters(Query))/binary >>;

serialize_req(#ecql_prepare{query = Query}) ->
    serialize_long_string(Query);

serialize_req(#ecql_execute{id = Id, query = Query}) ->
    << (serialize_short_bytes(Id))/binary, (serialize_query_parameters(Query))/binary >>;

serialize_req(#ecql_batch{type = Type, queries = Queries,
                          consistency = Consistency,
                          with_names = WithNames,
                          serial_consistency = SerialConsistency,
                          timestamp = Timestamp}) ->
    QueriesBin = << <<(serialize_batch_query(Query))/binary>> || Query <- Queries >>,

    Flags = <<0:4,
              (flag(WithNames)):1,
              (flag(Timestamp)):1,
              (flag(SerialConsistency)):1,
              0:1>>,

    Parameters =
        [{serial_consistency, SerialConsistency}
         || flag(SerialConsistency) == 1 ] ++
        [{timestamp, Timestamp} || flag(Timestamp) == 1],

    ParamtersBin = << <<(serialize_parameter(Name, Val))/binary>> || {Name, Val} <- Parameters >>,
    <<Type:?byte, (length(Queries)):?short, QueriesBin/binary, Consistency:?short, Flags/binary, ParamtersBin/binary>>;

serialize_req(#ecql_register{event_types = EventTypes}) ->
    serialize_string_list(EventTypes).

serialize_batch_query(#ecql_batch_query{kind = 0, query_or_id = Str, values = Values}) ->
    <<0:?byte, (serialize_long_string(Str))/binary, (serialize_batch_query_values(Values))/binary>>;

serialize_batch_query(#ecql_batch_query{kind = 1, query_or_id = Id, values = Values}) ->
    <<1:?byte, (serialize_short_bytes(Id))/binary, (serialize_batch_query_values(Values))/binary>>.

serialize_batch_query_values([]) ->
    <<0:?short>>;
serialize_batch_query_values([H|_] = Values) when is_tuple(H) ->
    ValuesBin = << <<(serialize_string(Name))/binary, (serialize_bytes(Val))/binary>> || {Name, Val} <- Values >>,
    << (length(Values)):?short, ValuesBin/binary>>;

serialize_batch_query_values([H|_] = Values) when is_binary(H) ->
    ValuesBin = << <<(serialize_bytes(Val))/binary>> || Val <- Values >>,
    << (length(Values)):?short, ValuesBin/binary>>.

serialize_query_parameters(#ecql_query{consistency = Consistency,
                                       values = Values,
                                       skip_metadata = SkipMetadata,
                                       result_page_size = PageSize,
                                       paging_state = PagingState,
                                       serial_consistency = SerialConsistency,
                                       timestamp = Timestamp} = Query) ->
    Flags = <<0:1, (flag(values, Values)):1, (flag(Timestamp)):1, (flag(SerialConsistency)):1,
              (flag(PagingState)):1, (flag(PageSize)):1, (flag(SkipMetadata)):1, (flag(Values)):1>>,

    [_Q, _C, _F|Parameters] = ?record_to_proplist(ecql_query, Query),

    Bin = << <<(serialize_parameter(Name, Val))/binary>> || {Name, Val} <- Parameters, Val =/= undefined >>,

    <<Consistency:?short, Flags/binary, Bin/binary>>.

serialize_parameter(values, []) ->
    <<>>;

serialize_parameter(values, [H |_] = Vals) when is_tuple(H) ->
    Bin = << <<(serialize_string(Name))/binary, (serialize_bytes(Val))/binary>> || {Name, Val} <- Vals >>,
    <<(length(Vals)):?short, Bin/binary>>;

serialize_parameter(values, [H |_] = Vals) when is_binary(H) ->
    Bin = << <<(serialize_bytes(Val))/binary>> || Val <- Vals >>,
    <<(length(Vals)):?short, Bin/binary>>;

serialize_parameter(skip_metadata, _) ->
    <<>>;

serialize_parameter(result_page_size, PageSize) ->
    <<PageSize:?int>>;

serialize_parameter(paging_state, PagingState) ->
    serialize_bytes(PagingState);

serialize_parameter(serial_consistency, SerialConsistency) ->
    <<SerialConsistency:?short>>;

serialize_parameter(timestamp, Timestamp) ->
    <<Timestamp:?long>>.

%%serialize_string_multimap(Map) ->
%%    Bin = << <<(serialize_string(K))/binary, (serialize_string_list(L))/binary>> || {K, L} <- Map >>,
%%    <<(length(Map)):?short, Bin/binary>>.

serialize_string_map(Map) ->
    Bin = << <<(serialize_string(K))/binary, (serialize_string(V))/binary>> || {K, V} <- Map >>,
    <<(length(Map)):?short, Bin/binary>>.

serialize_string_list(List) ->
    Bin = << <<(serialize_string(S))/binary>> || S <- List >>,
    <<(length(List)):?short, Bin/binary>>.

serialize_string(S) ->
    <<(size(S)):?short, S/binary>>.

serialize_long_string(S) ->
    <<(size(S)):?int, S/binary>>.

serialize_short_bytes(Bytes) ->
    <<(size(Bytes)):?short, Bytes/binary>>.

serialize_bytes(Bin) ->
    ecql_types:to_bytes(Bin).

%%serialize_option_list(Options) ->
%%    Bin = << <<(serialize_option(Opt))/binary>> || Opt <- Options >>,
%%    <<(size(Options)):?short, Bin/binary>>.

%%serialize_option({Id, Val}) ->
    %%TODO:...
%%    <<>>.

result_kind(16#01) -> void;
result_kind(16#02) -> rows;
result_kind(16#03) -> set_keyspace;
result_kind(16#04) -> prepared;
result_kind(16#05) -> schema_change.

flag(values, undefined)                   -> 0;
flag(values, [])                          -> 0;
flag(values, [Val|_]) when is_binary(Val) -> 0;
flag(values, [Val|_]) when is_tuple(Val)  -> 1.

flag(undefined) -> 0;
flag([])        -> 0;
flag(false)     -> 0;
flag(true)      -> 1;
flag(_Val)      -> 1.

bool(1) -> true;
bool(0) -> false.

