
%%------------------------------------------------------------------------------
%% Common Type
%%------------------------------------------------------------------------------
-define(byte,   1/big-signed-unit:8).
-define(short,  1/big-signed-unit:16).
-define(int,    1/big-signed-unit:32).
-define(long,   1/big-signed-unit:64).
-define(float,  1/big-float-unit:32).
-define(double, 1/big-float-unit:64).
-define(uuid,   16/binary).

%%------------------------------------------------------------------------------
%% Cassandra Type
%%------------------------------------------------------------------------------

%% Custom: the value is a [string], see above.
-define(TYPE_CUSTOM,    16#00).
-define(TYPE_ASCII,     16#01).
-define(TYPE_BIGINT,    16#02).
-define(TYPE_BLOB,      16#03).
-define(TYPE_BOOLEAN,   16#04).
-define(TYPE_COUNTER,   16#05). 
-define(TYPE_DECIMAL,   16#06).
-define(TYPE_DOUBLE,    16#07).
-define(TYPE_FLOAT,     16#08).
-define(TYPE_INT,       16#09).
-define(TYPE_TIMESTAMP, 16#0B).
-define(TYPE_UUID,      16#0C).
-define(TYPE_VARCHAR,   16#0D).
-define(TYPE_VARINT,    16#0E).
-define(TYPE_TIMEUUID,  16#0F).
-define(TYPE_INET,      16#10).
%% the value is an [option], representing the type of the elements of the list.
-define(TYPE_LIST,      16#20).
%% the value is two [option], representing the types of the keys and values of the map
-define(TYPE_MAP,       16#21).
%% the value is an [option], representing the type of the elements of the set
-define(TYPE_SET,       16#22).
%% the value is <ks><udt_name><n><name_1><type_1>...<name_n><type_n>
-define(TYPE_UDT,       16#30).
-define(TYPE_TUPLE,     16#31).

