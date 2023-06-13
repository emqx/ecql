%%--------------------------------------------------------------------
%% Copyright (c) 2022-2023 EMQ Technologies Co., Ltd. All Rights Reserved.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%%     http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.
%%--------------------------------------------------------------------

%% Note: this module CAN'T be hot-patched to avoid invalidating the
%% closures, so it must not be changed.
-module(ecql_secret).

%% API:
-export([wrap/1, unwrap/1, map/2]).

-export_type([t/1]).

-opaque t(T) :: T | fun(() -> t(T)).

%%================================================================================
%% API funcions
%%================================================================================

wrap(Term) ->
    fun() ->
        Term
    end.

unwrap(Term) when is_function(Term, 0) ->
    %% Handle potentially nested funs
    unwrap(Term());
unwrap(Term) ->
    Term.

%% a functor to make the security transferable
map(Fun, Term) ->
    %% lazy evaluation may not be necessary.
    wrap(Fun(unwrap(Term))).
