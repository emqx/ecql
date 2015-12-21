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
%%% @doc CQL Driver.
%%%
%%% @author Feng Lee <feng@emqtt.io>
%%%-----------------------------------------------------------------------------
-module(ecql).

-behaviour(gen_fsm).

-include("ecql.hrl").

-include("ecql_frame.hrl").

-import(proplists, [get_value/2, get_value/3]).

%% API Function Exports
-export([start_link/1, start_link/2]).

%% gen_fsm Function Exports
-export([connected/2, connected/3, disconnected/2, disconnected/3]).

-export([init/1, handle_event/3, handle_sync_event/4, handle_info/3,
         terminate/3, code_change/4]).

-type host() :: inet:ip_address() | inet:hostname().

-type option() :: {host, host()}
                | {port, inet:port_number()}
                | {ssl,  boolean()}
                | {ssl_opts, [ssl:ssl_option()]}
                | {timeout,  timeout()}
                | {logger, atom() | {atom(), atom()}}.

-record(state, {nodes     :: [{host(), inet:port_number()}],
                transport :: tcp | ssl,
                socket    :: inet:socket(),
                receiver  :: pid(),
                requests  :: dict:dict(),
                logger    :: gen_logger:logmod(),
                tcp_opts  :: [gen_tcp:connect_option()]}).

%% API Function Definitions

-spec start_link([option()]) -> {ok, pid()} | {error, any()}.
start_link(Opts) ->
    start_link(Opts, []).

-spec start_link([option()], [gen_tcp:connect_option()])
        -> {ok, pid()} | {error, any()}.
start_link(Opts, TcpOpts) ->
    case gen_fsm:start_link(?MODULE, [Opts], []) of
        {ok, Pid} ->
            connect(Pid, TcpOpts);
        {error, Error} ->
            {error, Error}
    end.

connect(Pid, TcpOpts) ->
    case gen_fsm:sync_send_event(Pid, {connect, TcpOpts}) of
        ok             -> {ok, Pid};
        {error, Error} -> {error, Error}
    end.

%% gen_fsm Function Definitions

init([Opts, TcpOpts]) ->
    {ok, connected, #state{}}.

connected(_Event, State) ->
    {next_state, state_name, State}.

connected(_Event, _From, State) ->
    {reply, ok, state_name, State}.

disconnected(_Event, State) ->
    {next_state, state_name, State}.

disconnected(_Event, _From, State) ->
    {reply, ok, state_name, State}.

handle_event(_Event, StateName, State) ->
    {next_state, StateName, State}.

handle_sync_event(_Event, _From, StateName, State) ->
    {reply, ok, StateName, State}.

handle_info(_Info, StateName, State) ->
    {next_state, StateName, State}.

terminate(_Reason, _StateName, _State) ->
    ok.

code_change(_OldVsn, StateName, State, _Extra) ->
    {ok, StateName, State}.

%% Internal Function Definitions

