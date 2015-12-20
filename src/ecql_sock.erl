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
%%% @doc CQL Socket and Receiver.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------

-module(ecql_sock).

-include("ecql_frame.hrl").

%% API
-export([connect/5, controlling_process/2, send/2, close/1, stop/1]).

-export([sockname/1, sockname_s/1, setopts/2, getstat/2]).

%% Internal export
-export([receiver/2, receiver_loop/3]).

%% 60 (secs)
-define(TIMEOUT, 60000).

-define(TCPOPTIONS, [
    binary,
    {packet,    raw},
    {reuseaddr, true},
    {nodelay,   true},
    {active, 	false},
    {reuseaddr, true},
    {send_timeout,  ?TIMEOUT}]).

-define(SSLOPTIONS, [{depth, 0}]).

-record(ssl_socket, {tcp, ssl}).

-type ssl_socket() :: #ssl_socket{}.

-define(IS_SSL(Socket), is_record(Socket, ssl_socket)).

%% @doc Connect to Cassandra with TCP or SSL transport
-spec connect(ClientPid, Transport, Host, Port, TcpOpts) -> {ok, Socket, Receiver} | {error, term()} when
    ClientPid   :: pid(),
    Transport   :: tcp | ssl,
    Host        :: inet:ip_address() | string(),
    Port        :: inet:port_number(),
    TcpOpts     :: [gen_tcp:connect_option()],
    Socket      :: inet:socket() | ssl_socket(),
    Receiver    :: pid().
connect(ClientPid, Transport, Host, Port, TcpOpts) when is_pid(ClientPid) ->
    case connect(Transport, Host, Port, TcpOpts) of
        {ok, Socket} ->
            ReceiverPid = spawn_link(?MODULE, receiver, [ClientPid, Socket]),
            controlling_process(Socket, ReceiverPid),
            {ok, Socket, ReceiverPid};
        {error, Reason} ->
            {error, Reason}
    end.

-spec connect(Transport, Host, Port, TcpOpts) -> {ok, Socket} | {error, any()} when
    Transport   :: tcp | ssl,
    Host        :: inet:ip_address() | string(),
    Port        :: inet:port_number(),
    TcpOpts     :: [gen_tcp:connect_option()],
    Socket      :: inet:socket() | ssl_socket().
connect(tcp, Host, Port, TcpOpts) ->
    gen_tcp:connect(Host, Port, merge_opts(?TCPOPTIONS, TcpOpts), ?TIMEOUT);
connect(ssl, Host, Port, TcpOpts) ->
    case gen_tcp:connect(Host, Port, merge_opts(?TCPOPTIONS, TcpOpts), ?TIMEOUT) of
        {ok, Socket} ->
            case ssl:connect(Socket, ?SSLOPTIONS, ?TIMEOUT) of
                {ok, SslSocket} -> {ok, #ssl_socket{tcp = Socket, ssl = SslSocket}};
                {error, SslReason} -> {error, SslReason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% @doc Socket controlling process
controlling_process(Socket, Pid) when is_port(Socket) ->
    gen_tcp:controlling_process(Socket, Pid);
controlling_process(#ssl_socket{ssl = SslSocket}, Pid) ->
    ssl:controlling_process(SslSocket, Pid).

%% @doc Send Frame and Data
-spec send(Socket, Data) -> ok when 
    Socket  :: inet:socket() | ssl_socket(),
    Data    :: binary().
send(Socket, Data) when is_port(Socket) ->
    gen_tcp:send(Socket, Data);
send(#ssl_socket{ssl = SslSocket}, Data) ->
    ssl:send(SslSocket, Data).

%% @doc Close Socket.
-spec close(Socket :: inet:socket() | ssl_socket()) -> ok.
close(Socket) when is_port(Socket) ->
    gen_tcp:close(Socket);
close(#ssl_socket{ssl = SslSocket}) ->
    ssl:close(SslSocket).

%% @doc Stop Receiver.
-spec stop(Receiver :: pid()) -> ok.
stop(Receiver) ->
    Receiver ! stop.

%% @doc Set socket options.
setopts(Socket, Opts) when is_port(Socket) ->
    inet:setopts(Socket, Opts);
setopts(#ssl_socket{ssl = SslSocket}, Opts) ->
    ssl:setopts(SslSocket, Opts).

%% @doc Get socket stats.
-spec getstat(Socket, Stats) -> {ok, Values} | {error, any()} when 
    Socket  :: inet:socket() | ssl_socket(),
    Stats   :: list(),
    Values  :: list().
getstat(Socket, Stats) when is_port(Socket) ->
    inet:getstat(Socket, Stats);
getstat(#ssl_socket{tcp = Socket}, Stats) -> 
    inet:getstat(Socket, Stats).

%% @doc Socket name.
-spec sockname(Socket) -> {ok, {Address, Port}} | {error, any()} when
    Socket  :: inet:socket() | ssl_socket(),
    Address :: inet:ip_address(),
    Port    :: inet:port_number().
sockname(Socket) when is_port(Socket) ->
    inet:sockname(Socket);
sockname(#ssl_socket{ssl = SslSocket}) ->
    ssl:sockname(SslSocket).

sockname_s(Sock) ->
    case sockname(Sock) of
        {ok, {Addr, Port}} ->
            {ok, lists:flatten(io_lib:format("~s:~p", [maybe_ntoab(Addr), Port]))};
        Error ->
            Error
    end.

%%%=============================================================================
%%% Internal functions
%%%=============================================================================

receiver(ClientPid, Socket) ->
    receiver_activate(ClientPid, Socket, ecql_frame:parser()).

receiver_activate(ClientPid, Socket, ParserFun) ->
    setopts(Socket, [{active, once}]),
    erlang:hibernate(?MODULE, receiver_loop, [ClientPid, Socket, ParserFun]).

receiver_loop(ClientPid, Socket, ParserFun) ->
    receive
        {tcp, Socket, Data} ->
            case parse_received_data(ClientPid, Data, ParserFun) of
                {ok, NewParserFun} ->
                    receiver_activate(ClientPid, Socket, NewParserFun);
                {error, Error} ->
                    gen_fsm:send_all_state_event(ClientPid, {frame_error, Error})
            end;
        {tcp_error, Socket, Reason} ->
            connection_lost(ClientPid, {tcp_error, Reason});
        {tcp_closed, Socket} ->
            connection_lost(ClientPid, tcp_closed);
        {ssl, _SslSocket, Data} ->
            case parse_received_data(ClientPid, Data, ParserFun) of
                {ok, NewParserFun} ->
                    receiver_activate(ClientPid, Socket, NewParserFun);
                {error, Error} ->
                    gen_fsm:send_all_state_event(ClientPid, {frame_error, Error})
            end;
        {ssl_error, _SslSocket, Reason} ->
            connection_lost(ClientPid, {ssl_error, Reason});
        {ssl_closed, _SslSocket} ->
            connection_lost(ClientPid, ssl_closed);
        stop -> 
            close(Socket)
    end.

parse_received_data(_ClientPid, <<>>, ParserFun) ->
    {ok, ParserFun};

parse_received_data(ClientPid, Data, ParserFun) ->
    case ParserFun(Data) of
        {more, NewParserFun} ->
            {ok, NewParserFun};
        {ok, Frame, Rest} ->
            gen_fsm:send_event(ClientPid, {received, Frame}),
            parse_received_data(ClientPid, Rest, ecql_frame:parser());
        {error, Error} ->
            {error, Error}
    end.

connection_lost(ClientPid, Reason) ->
    gen_fsm:send_all_state_event(ClientPid, {connection_lost, Reason}).

maybe_ntoab(Addr) when is_tuple(Addr) -> ntoab(Addr);
maybe_ntoab(Host)                     -> Host.

ntoa({0,0,0,0,0,16#ffff,AB,CD}) ->
    inet_parse:ntoa({AB bsr 8, AB rem 256, CD bsr 8, CD rem 256});
ntoa(IP) ->
    inet_parse:ntoa(IP).

ntoab(IP) ->
    Str = ntoa(IP),
    case string:str(Str, ":") of
        0 -> Str;
        _ -> "[" ++ Str ++ "]"
    end.

merge_opts(Defaults, Options) ->
    lists:foldl(
        fun({Opt, Val}, Acc) ->
                case lists:keymember(Opt, 1, Acc) of
                    true ->
                        lists:keyreplace(Opt, 1, Acc, {Opt, Val});
                    false ->
                        [{Opt, Val}|Acc]
                end;
            (Opt, Acc) ->
                case lists:member(Opt, Acc) of
                    true -> Acc;
                    false -> [Opt | Acc]
                end
        end, Defaults, Options).

