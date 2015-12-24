
-module(ecql_types_tests).

-ifdef(TEST).

-include("ecql_types.hrl").

-include_lib("eunit/include/eunit.hrl").

-import(ecql_types, [name/1, value/1]).

-import(ecql_types, [encode/2, decode/3]).

name_value_test() ->
    ?assertEqual(custom,    name(value(custom))),
    ?assertEqual(ascii,     name(value(ascii))),
    ?assertEqual(bigint,    name(value(bigint))),
    ?assertEqual(blob,      name(value(blob))),
    ?assertEqual(boolean,   name(value(boolean))),
    ?assertEqual(counter,   name(value(counter))),
    ?assertEqual(decimal,   name(value(decimal))),
    ?assertEqual(double,    name(value(double))),
    ?assertEqual(float,     name(value(float))),
    ?assertEqual(int,       name(value(int))),
    ?assertEqual(timestamp, name(value(timestamp))),
    ?assertEqual(uuid,      name(value(uuid))),
    ?assertEqual(varchar,   name(value(varchar))),
    ?assertEqual(varint,    name(value(varint))),
    ?assertEqual(timeuuid,  name(value(timeuuid))),
    ?assertEqual(inet,      name(value(inet))),
    ?assertEqual(list,      name(value(list))),
    ?assertEqual(map,       name(value(map))),
    ?assertEqual(set,       name(value(set))),
    ?assertEqual(udt,       name(value(udt))),
    ?assertEqual(tuple,     name(value(tuple))).

encode_decode_test() ->
    Ascii = <<"abcd1990">>,
    ?assertMatch({Ascii, <<>>}, decode(ascii, size(Ascii), encode(ascii, Ascii))),
    Bigint = 123456,
    ?assertMatch({Bigint, <<>>}, decode(bigint, 8, encode(bigint, Bigint))),
    Blob = <<"abc">>,
    ?assertMatch({Blob, <<>>}, decode(blob, size(Blob), encode(blob, Blob))),
    ?assertMatch({true, <<>>},  decode(boolean, 1, encode(boolean, true))),
    ?assertMatch({false, <<>>}, decode(boolean, 1, encode(boolean, false))),
    Counter = 19383,
    ?assertMatch({Counter, <<>>}, decode(counter, 8, encode(counter, Counter))),
    Decimal = {128, 1},
    ?assertMatch({Decimal, <<>>}, decode(decimal, 6, encode(decimal, Decimal))),
    Double = 1.1,
    {DecodeDouble, <<>>} = decode(double, 8, encode(double, Double)),
    ?assertEqual(<<Double:?double>>, <<DecodeDouble:?double>>),
    {DecodeFloat, <<>>} = decode(float, 4, encode(float, Double)),
    ?assertEqual(<<Double:?float>>, <<DecodeFloat:?float>>),

    Ip = {1,2,3,4},
    ?assertMatch({Ip, <<>>}, decode(inet, 4, encode(inet, Ip))),
    Ipv6 = {1,2,3,4,5,6,7,8},
    ?assertMatch({Ipv6, <<>>}, decode(inet, 16, encode(inet, Ipv6))),

    Int = 10,
    ?assertEqual({Int, <<>>}, decode(int, 4, encode(int, Int))),

    List = [<<"hello">>, <<"haha">>],
    ListBin = encode({list, text}, List),
    ?assertMatch({List, <<>>}, decode({list, text}, size(ListBin), ListBin)),

    Map = [{<<"key">>, 1234}, {<<"key2">>, 4567}],
    MapBin = encode({map, {text, int}}, Map),
    ?assertMatch({Map, <<>>}, decode({map, {text, int}}, size(MapBin), MapBin)),

    Set = [1, 2, 3],
    SetBin = encode({set, bigint}, Set),
    ?assertMatch({Set, <<>>}, decode({set, bigint}, size(SetBin), SetBin)), 

    {MegaSecs, Secs, _MicroSecs} = os:timestamp(),
    Timestamp = MegaSecs * 1000000 + Secs,
    ?assertMatch({Timestamp, <<>>}, decode(timestamp, 8, encode(timestamp, Timestamp))),

    Varint = 127,
    VarintBin = encode(varint, Varint),
    ?assertEqual(1, size(VarintBin)),
    ?assertEqual({Varint, <<>>}, decode(varint, 1, encode(varint, Varint))),

    Varint2 = 129,
    VarintBin2 = encode(varint, Varint2),
    ?assertEqual(2, size(VarintBin2)),
    ?assertEqual({Varint2, <<>>}, decode(varint, 2, encode(varint, Varint2))),

    Tuple = {1, <<"haha">>, 2},
    Types = {bigint, text, counter},
    TupleBin = encode({tuple, Types}, Tuple),
    ?assertEqual({Tuple, <<>>}, decode({tuple, Types}, size(TupleBin), TupleBin)).

-endif.
