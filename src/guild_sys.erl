%% Copyright 2106 TensorHub, Inc.
%%
%% Licensed under the Apache License, Version 2.0 (the "License");
%% you may not use this file except in compliance with the License.
%% You may obtain a copy of the License at
%%
%% http://www.apache.org/licenses/LICENSE-2.0
%%
%% Unless required by applicable law or agreed to in writing, software
%% distributed under the License is distributed on an "AS IS" BASIS,
%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%% See the License for the specific language governing permissions and
%% limitations under the License.

-module(guild_sys).

-export([start_link/0, gpu_attrs/0, system_attrs/0]).

-export([handle_msg/3]).

-behavior(e2_service).

-record(state, {gpu_attrs, sys_attrs}).

-define(part(I), element(I, Parts)).

%% ===================================================================
%% Start
%% ===================================================================

start_link() ->
    e2_service:start_link(?MODULE, #state{}, [registered]).

%% ===================================================================
%% API
%% ===================================================================

gpu_attrs() ->
    e2_service:call(?MODULE, gpu_attrs).

system_attrs() ->
    e2_service:call(?MODULE, sys_attrs).

%% ===================================================================
%% Messages
%% ===================================================================

handle_msg(gpu_attrs, _From, State) ->
    {Attrs, Next} = ensure_gpu_attrs(State),
    {reply, Attrs, Next};
handle_msg(sys_attrs, _From, State) ->
    {Attrs, Next} = ensure_sys_attrs(State),
    {reply, Attrs, Next}.

%% ===================================================================
%% GPU attrs
%% ===================================================================

ensure_gpu_attrs(#state{gpu_attrs=undefined}=S) ->
    Attrs = gpu_attrs_(),
    {Attrs, S#state{gpu_attrs=Attrs}};
ensure_gpu_attrs(#state{gpu_attrs=Attrs}=State) ->
    {Attrs, State}.

gpu_attrs_() ->
    ensure_exec_support(),
    case exec:run(guild_app:priv_bin("gpu-attrs"), [sync, stdout, stderr]) of
        {ok, [{stdout, Out}]} ->
            parse_gpu_attrs(Out);
        {error, [{exit_status, 32512}|_]} ->
            empty_gpu_attrs();
        {error, Err} ->
            guild_log:internal(
              "Error reading gpu attrs: ~p~n", [Err]),
            []
    end.

ensure_exec_support() ->
    %% Exec support is lazy as it starts a port process.
    guild_app:init_support(exec).

parse_gpu_attrs(Out) ->
    [parse_gpu_attrs_line(Line) || Line <- re:split(Out, "\n", [trim])].

parse_gpu_attrs_line(Line) ->
    Parts = list_to_tuple(re:split(Line, ", ", [{return, list}])),
    #{index          => ?part(1),
      name           => ?part(2),
      driver_version => ?part(3),
      bus_id         => ?part(4),
      link_gen       => ?part(5),
      link_gen_max   => ?part(6),
      link_width     => ?part(7),
      link_width_max => ?part(8),
      display_mode   => ?part(9),
      display_active => ?part(10),
      vbios_version  => ?part(11),
      pstate         => ?part(12),
      memory         => ?part(13),
      compute_mode   => ?part(14),
      power_limit    => ?part(15)
     }.

empty_gpu_attrs() -> [].

%% ===================================================================
%% Sys attrs
%% ===================================================================

ensure_sys_attrs(#state{sys_attrs=undefined}=S) ->
    Attrs = sys_attrs_(),
    {Attrs, S#state{sys_attrs=Attrs}};
ensure_sys_attrs(#state{sys_attrs=Attrs}=State) ->
    {Attrs, State}.

sys_attrs_() ->
    ensure_exec_support(),
    case exec:run(guild_app:priv_bin("sys-attrs"), [sync, stdout, stderr]) of
        {ok, [{stdout, Out}]} ->
            parse_sys_attrs(Out);
        {error, Err} ->
            guild_log:internal(
              "Error reading sys attrs: ~p~n", [Err]),
            []
    end.

parse_sys_attrs(Out) ->
    [parse_sys_attrs_line(Line) || Line <- re:split(Out, "\n", [trim])].

parse_sys_attrs_line(Line) ->
    Parts = list_to_tuple(re:split(Line, ", ", [{return, list}])),
    #{cpu_model      => ?part(1),
      cpu_cores      => ?part(2)
     }.
