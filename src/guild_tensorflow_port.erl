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

-module(guild_tensorflow_port).

-behavior(e2_service).

-export([start_link/0, load_image/2]).

-export([init/1, handle_msg/3]).

-record(state, {exec_pid, exec_ospid, callers, buf}).

%% ===================================================================
%% Start / init
%% ===================================================================

start_link() ->
    e2_service:start_link(?MODULE, [], [registered]).

init([]) ->
    process_flag(trap_exit, true),
    Exec = start_exec(),
    {ok, init_state(Exec)}.

start_exec() ->
    Args = [port_exe()],
    Opts = [stdout, stderr, stdin],
    {ok, Pid, OSPid} = guild_exec:run_link(Args, Opts),
    {Pid, OSPid}.

port_exe() ->
    guild_app:priv_bin("tensorflow-port").

init_state({ExecPid, ExecOSPid}) ->
    #state{
       callers=[],
       buf=[],
       exec_pid=ExecPid,
       exec_ospid=ExecOSPid}.

%% ===================================================================
%% API
%% ===================================================================

load_image(RunDir, Index) ->
    e2_service:call(?MODULE, {call, {load_image, RunDir, Index}}).

%% ===================================================================
%% Message dispatch
%% ===================================================================

handle_msg({call, Call}, From, State) ->
    handle_port_call(Call, From, State);
handle_msg({stdout, OSPid, Bin}, noreply, #state{exec_ospid=OSPid}=State) ->
    handle_stdout(Bin, State);
handle_msg({stderr, OSPid, Bin}, noreply, #state{exec_ospid=OSPid}=State) ->
    handle_stderr(Bin, State);
handle_msg({'EXIT', Pid, Reason}, noreply, #state{exec_pid=Pid}=State) ->
    handle_exec_exit(Reason, State).

%% ===================================================================
%% Port call
%% ===================================================================

handle_port_call(Call, From, State) ->
    Ref = dispatch_port_call(Call, State),
    Next = add_caller(From, Ref, Call, State),
    {noreply, Next}.

dispatch_port_call(Call, #state{exec_ospid=OSPid}) ->
    Ref = request_ref(),
    Request = encode_request(Ref, Call),
    ok = exec:send(OSPid, Request),
    Ref.

request_ref() -> rand:uniform(1000000).

encode_request(Ref, Call) ->
    iolist_to_binary([encode_ref(Ref), $\t, encode_call(Call), $\n]).

encode_ref(Ref) -> erlang:integer_to_list(Ref).

encode_call({load_image, Dir, Index}) ->
    ["load_image", $\t, Dir, $\t, integer_to_list(Index)].

add_caller(From, Ref, Call, #state{callers=Callers}=S) ->
    S#state{callers=[{Ref, Call, From}|Callers]}.

%% ===================================================================
%% Stdout
%% ===================================================================

handle_stdout(Bin, State) ->
    handle_split_stdout(binary:split(Bin, <<"\n\n">>), State).

handle_split_stdout([Part], State) ->
    {noreply, buffer(Part, State)};
handle_split_stdout([EOF, Rest], State) ->
    handle_response(buffer(EOF, State), Rest).

buffer(Bin, #state{buf=Buf}=S) -> S#state{buf=[Bin|Buf]}.

handle_response(#state{callers=[{Ref, Call, From}|Rest], buf=Buf}=S, NextBuf) ->
    {Ref, Resp} = decode_buffer(lists:reverse(Buf), Call),
    e2_service:reply(From, Resp),
    {noreply, S#state{callers=Rest, buf=new_buf(NextBuf)}}.

decode_buffer(Buf, Call) ->
    [RefBin, StatusBin|Rest] = (re:split(Buf, "\n")),
    Ref = binary_to_integer(RefBin),
    Status = binary_to_existing_atom(StatusBin, latin1),
    {Ref, decode_call_result(Status, Call, Rest)}.

decode_call_result(ok, {load_image, _, _}, Rest) ->
    {ok, Rest};
decode_call_result(error, _, Msg) ->
    {error, Msg}.

new_buf(<<>>) -> [];
new_buf(Next) -> [Next].

%% ===================================================================
%% Stderr
%% ===================================================================

handle_stderr(Bin, State) ->
    io:format(standard_error, "~s", [Bin]),
    {noreply, State}.

%% ===================================================================
%% Exec exited
%% ===================================================================

handle_exec_exit(normal, State) ->
    {stop, normal, State};
handle_exec_exit({exit_status, Status}, State) ->
    {stop, {exec_exit, exec:status(Status)}, State}.
