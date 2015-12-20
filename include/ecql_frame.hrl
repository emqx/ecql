
%% type
-define(byte, 8).
-define(int,  1/big-signed-unit:32).
-define(long, 1/big-signed-unit:64).
-define(short,1/big-signed-unit:16).
-define(uuid, 16/binary).

%% [consistency] A consistency level specification.
%% This is a [short] representing a consistency level with the following.

-define(ANY,          16#00).
-define(ONE,          16#01).
-define(TWO,          16#02).
-define(THREE,        16#03).
-define(QUORUM,       16#04).
-define(ALL,          16#05).
-define(LOCAL_QUORUM, 16#06).
-define(EACH_QUORUM,  16#07).
-define(SERIAL,       16#08).
-define(LOCAL_SERIAL, 16#09).
-define(LOCAL_ONE,    16#0A).

