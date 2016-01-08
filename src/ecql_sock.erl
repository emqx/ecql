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

%% API
-export([connect/6, controlling_process/2, send/2, close/1, stop/1]).

-export([sockname/1, sockname_s/1, setopts/2, getstat/2]).

%% Internal export
-export([receiver/3, receiver_loop/4]).

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

-define(IS_SSL(Sock), is_record(Sock, ssl_socket)).

%% @doc Connect to Cassandra with TCP or SSL transport
-spec connect(ClientPid, Transport, Host, Port, Opts, Logger) -> {ok, Sock, Receiver} | {error, term()} when
    ClientPid :: pid(),
    Transport :: tcp | ssl,
    Host      :: inet:ip_address() | string(),
    Port      :: inet:port_number(),
    Opts      :: {[gen_tcp:connect_option()], [ssl:ssl_option()]},
    Logger    :: gen_logger:logmod(),
    Sock      :: inet:socket() | ssl_socket(),
    Receiver  :: pid().
connect(ClientPid, Transport, Host, Port, Opts, Logger) when is_pid(ClientPid) ->
    case connect(Transport, Host, Port, Opts) of
        {ok, Sock} ->
            ReceiverPid = spawn_link(?MODULE, receiver, [ClientPid, Sock, Logger]),
            controlling_process(Sock, ReceiverPid),
            {ok, Sock, ReceiverPid};
        {error, Reason} ->
            {error, Reason}
    end.

-spec connect(Transport, Host, Port, Opts) -> {ok, Sock} | {error, any()} when
    Transport :: tcp | ssl,
    Host      :: inet:ip_address() | string(),
    Port      :: inet:port_number(),
    Opts      :: {[gen_tcp:connect_option()], [ssl:ssl_option()]},
    Sock      :: inet:socket() | ssl_socket().
connect(tcp, Host, Port, {TcpOpts, _}) ->
    case gen_tcp:connect(Host, Port, merge_opts(?TCPOPTIONS, TcpOpts), ?TIMEOUT) of
        {ok, Sock} -> tune_buffer(Sock),
                      {ok, Sock};
        Error      -> Error
    end;

connect(ssl, Host, Port, {TcpOpts, SslOpts}) ->
    case gen_tcp:connect(Host, Port, merge_opts(?TCPOPTIONS, TcpOpts), ?TIMEOUT) of
        {ok, Sock} ->
            tune_buffer(Sock),
            case ssl:connect(Sock, merge_opts(?SSLOPTIONS, SslOpts), ?TIMEOUT) of
                {ok, SslSock} -> {ok, #ssl_socket{tcp = Sock, ssl = SslSock}};
                Error -> Error
            end;
        Error ->
            Error
    end.

tune_buffer(Sock) ->
    {ok, [{recbuf, RecBuf}, {sndbuf, SndBuf}]}
        = inet:getopts(Sock, [recbuf, sndbuf]),
    inet:setopts(Sock, [{buffer, max(RecBuf, SndBuf)}]).

%% @doc Sock controlling process
-spec controlling_process(Sock, Pid) -> ok when
      Sock  :: inet:socket() | ssl_socket(),
      Pid   :: pid().
controlling_process(Sock, Pid) when is_port(Sock) ->
    gen_tcp:controlling_process(Sock, Pid);
controlling_process(#ssl_socket{ssl = SslSock}, Pid) ->
    ssl:controlling_process(SslSock, Pid).

%% @doc Send Frame and Data
-spec send(Sock, Data) -> ok when 
    Sock  :: inet:socket() | ssl_socket(),
    Data  :: iodata().
send(Sock, Data) when is_port(Sock) ->
    gen_tcp:send(Sock, Data);
send(#ssl_socket{ssl = SslSock}, Data) ->
    ssl:send(SslSock, Data).

%% @doc Close Sock.
-spec close(Sock :: inet:socket() | ssl_socket()) -> ok.
close(Sock) when is_port(Sock) ->
    gen_tcp:close(Sock);
close(#ssl_socket{ssl = SslSock}) ->
    ssl:close(SslSock).

%% @doc Stop Receiver.
-spec stop(Receiver :: pid()) -> stop.
stop(Receiver) ->
    Receiver ! stop.

%% @doc Set socket options.
setopts(Sock, Opts) when is_port(Sock) ->
    inet:setopts(Sock, Opts);
setopts(#ssl_socket{ssl = SslSock}, Opts) ->
    ssl:setopts(SslSock, Opts).

%% @doc Get socket stats.
-spec getstat(Sock, Stats) -> {ok, Values} | {error, any()} when 
    Sock   :: inet:socket() | ssl_socket(),
    Stats  :: list(),
    Values :: list().
getstat(Sock, Stats) when is_port(Sock) ->
    inet:getstat(Sock, Stats);
getstat(#ssl_socket{tcp = Sock}, Stats) -> 
    inet:getstat(Sock, Stats).

%% @doc Sock name.
-spec sockname(Sock) -> {ok, {Address, Port}} | {error, any()} when
    Sock    :: inet:socket() | ssl_socket(),
    Address :: inet:ip_address(),
    Port    :: inet:port_number().
sockname(Sock) when is_port(Sock) ->
    inet:sockname(Sock);
sockname(#ssl_socket{ssl = SslSock}) ->
    ssl:sockname(SslSock).

sockname_s(Sock) ->
    case sockname(Sock) of
        {ok, {Addr, Port}} ->
            {ok, io_lib:format("~s:~p", [maybe_ntoab(Addr), Port])};
        Error ->
            Error
    end.

%%% Receiver Loop
receiver(ClientPid, Sock, Logger) ->
    receiver_activate(ClientPid, Sock, ecql_frame:parser(), Logger).

receiver_activate(ClientPid, Sock, ParserFun, Logger) ->
    setopts(Sock, [{active, once}]),
    erlang:hibernate(?MODULE, receiver_loop, [ClientPid, Sock, ParserFun, Logger]).

receiver_loop(ClientPid, Sock, ParserFun, Logger) ->
    receive
        {tcp, Sock, Data} ->
            Logger:debug("[ecql~p] RECV: ~p", [ClientPid, Data]),
            case parse_received_data(ClientPid, Data, ParserFun) of
                {ok, NewParserFun} ->
                    receiver_activate(ClientPid, Sock, NewParserFun, Logger);
                {error, Error} ->
                    exit({frame_error, Error})
            end;
        {tcp_error, Sock, Reason} ->
            exit({tcp_error, Reason});
        {tcp_closed, Sock} ->
            exit(tcp_closed);
        {ssl, _SslSock, Data} ->
            case parse_received_data(ClientPid, Data, ParserFun) of
                {ok, NewParserFun} ->
                    receiver_activate(ClientPid, Sock, NewParserFun, Logger);
                {error, Error} ->
                    exit({frame_error, Error})
            end;
        {ssl_error, _SslSock, Reason} ->
            exit({ssl_error, Reason});
        {ssl_closed, _SslSock} ->
            exit(ssl_closed);
        stop -> 
            close(Sock)
    end.

parse_received_data(_ClientPid, <<>>, ParserFun) ->
    {ok, ParserFun};

parse_received_data(ClientPid, Data, ParserFun) ->
    case ParserFun(Data) of
        {more, NewParserFun} ->
            {ok, NewParserFun};
        {ok, Frame, Rest} ->
            gen_fsm:send_event(ClientPid, Frame),
            parse_received_data(ClientPid, Rest, ecql_frame:parser());
        {error, Error} ->
            {error, Error}
    end.

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

