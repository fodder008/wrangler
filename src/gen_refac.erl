%% Copyright (c) 2010, Huiqing Li, Simon Thompson
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions are met:
%%     %% Redistributions of source code must retain the above copyright
%%       notice, this list of conditions and the following disclaimer.
%%     %% Redistributions in binary form must reproduce the above copyright
%%       notice, this list of conditions and the following disclaimer in the
%%       documentation and/or other materials provided with the distribution.
%%     %% Neither the name of the copyright holders nor the
%%       names of its contributors may be used to endorse or promote products
%%       derived from this software without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS ''AS IS''
%% AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE 
%% IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE 
%% ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDERS AND CONTRIBUTORS 
%% BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR 
%% CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF 
%% SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR 
%% BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, 
%% WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR 
%% OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF 
%% ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
%%@version 0.1 
%%@author  Huiqing Li <H.Li@kent.ac.uk>
%%
%%
%%@doc This module defines the `gen_refac' behaviour. It provides a 
%% high-level abstraction of the logic work-flow of a refactoring 
%% process. A user-interactive refactoring 
%% process in Emacs generally works in the following way : the user first
%% selects the focus of interest by either pointing the cursor to a
%% particular program entity or by highlighting, then invokes the 
%% refactoring command; in case that the refactoring needs certain 
%% initial inputs from the user, it will prompt the user to input 
%% the values from the mini-buffer. After all these interactions,
%% the refactor engine starts the pre-condition checking to
%% make sure that performing the refactoring initiated by the user
%% will not change the behaviour of the program; the refactorer  
%% continues to carry out the program transformation if the pre-condition
%% passes, otherwise aborts the refactoring process and returns the reason
%% for failure.
%%
%% The idea behind this module is that the user module provides functions 
%% to handle different parts of the refactoring process that is particular 
%% to that refactoring, while `gen_refac' handles the parts that are common 
%% to all refactorings.
%%  
%% The user module should export:
%% ```input_pars() 
%%      ===> [string()]'''
%%  `input_pars' returns the list of prompt strings to be used when 
%%   the refactorer asks the user for input. There should be one 
%%   prompt string for each input.
%% ```select_focus(Args::#args{}) 
%%       ===> none|{ok, term()}|{error, Reason}'''
%%  `select_pars' returns the focus of interest selected by the user. 
%%   This function should return `none' if no focus selection is needed;
%%   `{error, Reason}' if the user didn't select the kind of entity 
%%   expected; or `{ok, term()' when a valid focus of interest has been
%%   selected.
%%  ```pre_cond_check(Args::#args{})
%%       ===> ok | {error, Reason}'''
%%   This function checks whether the pre-conditions of the refactoring 
%%   hold, and returns `ok' if the pre-condition checking passes, otherwise
%%   `{error, Reason}'.
%% ```transform(Args::#args()) 
%%      ===> {ok, [{filename(), syntaxTree()}] | {error, Reason}}'''
%%   Function `transform' carries out the transformation part of the 
%%   refactorings. If the refactoring succeeds, it returns the list of
%%   file names together with their new AST (only files that have been 
%%   changed need to be returned); otherwise `{error, Reason}'.
%%
%% Record `args' defines the data structure that is passed through, and also modified by, the different phases 
%% of the refactoring.
%%  ```-record(args,{current_file_name :: filename(),         %% the file name of the current Erlang buffer.
%%                   cursor_pos        :: pos(),              %% the current cursor position.
%%                   highlight_range   :: {pos(), pos()},     %% the start and end location of the highlighted code if there is any.
%%                   user_inputs       :: [string()],         %% the data inputted by the user.
%%                   focus_sel         :: any(),              %% the focus of interest selected by the user.
%%                   search_paths      ::[dir()|filename()],  %% the list of directories or files which specify the scope of the project.
%%                   tabwidth =8        ::integer()           %% the number of white spaces denoted by a tab key.
%%                  }).'''
%%
%% Some example refactorings implemented using the Wrangler API:
%%<ul>
%%<li>
%%<a href="file:refac_swap_args.erl" > Swap arguments of a function;</a>.
%%</li>
%%<li>
%%<a href="file:refac_specialise.erl"> Specialise a function definition; </a>
%%</li>
%%<li>
%%<a href="file:refac_apply_to_remote_call.erl"> Apply to remote function call; </a>
%%</li>
%%<li>
%%<a href="file:refac_intro_import.erl">Introduce an import attribute; </a>
%%</li>
%%<li>
%%<a href="file:refac_remove_import.erl">Remove an import attribute;</a>
%%</li>
%%<li>
%%<a href="file:refac_list.erl"> Various list-related transformations;</a>
%%</li>
%%<li>
%%<a href="file:refac_batch_rename_fun.erl"> Batch renaming of function names from camelCaseto camel_case. </a>
%%</li>
%%</ul>
%%</doc>
%%</ul>
%% Some example refactorings implemented using the Wrangler API:
%%<ul>
%%<li>
%%<a href="file:refac_swap_args.erl" > Swap arguments of a function;</a>.
%%</li>
%%<li>
%%<a href="file:refac_specialise.erl"> Specialise a function definition; </a>
%%</li>
%%<li>
%%<a href="file:refac_apply_to_remote_call.erl"> Apply to remote function call; </a>
%%</li>
%%<li>
%%<a href="file:refac_intro_import.erl">Introduce an import attribute; </a>
%%</li>
%%<li>
%%<a href="file:refac_remove_import.erl">Remove an import attribute;</a>
%%</li>
%%<li>
%%<a href="file:refac_list.erl"> Various list-related transformations;</a>
%%</li>
%%</ul>
%%</doc>


-module(gen_refac).

-export([run_refac/2, 
         input_pars/1]).

-export([behaviour_info/1]).

-include("../include/gen_refac.hrl").

%%@private
-spec behaviour_info(atom()) -> 'undefined' | [{atom(), arity()}].
behaviour_info(callbacks) ->
    [{input_pars,0}, {select_focus,1}, 
     {pre_cond_check, 1}, {transform, 1}].

-spec(select_focus(Module::module(), Args::[term()]) ->
             {ok, term()} | {error, term()}). 
select_focus(Module, Args) ->
    apply(Module, select_focus, [Args]).

-spec(pre_cond_check(Module::module(), Args::[term()]) ->
             ok | {error, term()}).
pre_cond_check(Module, Args) ->
    apply(Module, pre_cond_check, [Args]).

-spec(transform(Module::module(), Args::[term()]) ->
             {ok, [{filename(), filename(), syntaxTree()}]} |
             {error, term()}).
transform(Module, Args) ->
    apply(Module, transform, [Args]).

%%@doc The interface function for invoking a refactoring defined 
%% in module `ModName'.
%%@spec(run_refac(Module::module(), Args::[term()]) ->
%%            {ok, string()} | {error, term()}).
-spec(run_refac(Module::module(), Args::[term()]) ->
             {ok, string()} | {error, term()}).
run_refac(ModName, Args=[CurFileName, [Line,Col],
                         [[StartLine, StartCol],
                          [EndLn, EndCol]], UserInputs,
                         SearchPaths, TabWidth]) ->
    ?wrangler_io("\nCMD: ~p:run_refac(~p,~p).\n",
		 [?MODULE, ModName, Args]),
    Module = if is_list(ModName) ->
                     list_to_atom(ModName);
                true ->
                    ModName
             end,
    Args0=#args{current_file_name=CurFileName,
                cursor_pos = {Line, Col},
                highlight_range = {{StartLine, StartCol},
                                   {EndLn, EndCol}},
                user_inputs = UserInputs,
                search_paths = SearchPaths,
                tabwidth = TabWidth},
    case select_focus(Module, Args0) of
        {ok, Sel} ->
            Args1 = Args0#args{focus_sel=Sel},
            case pre_cond_check(Module, Args1) of
                ok -> 
                    case transform(Module,Args1) of
                        {ok, Res} ->
                            refac_write_file:write_refactored_files(
                              Res, 'emacs', TabWidth, "");
                        {error, Reason} ->
                            {error, Reason}
                    end;
                {error, Reason} ->
                    {error, Reason}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%%@private
input_pars(CallBackMod) ->
    Res =input_pars_1(CallBackMod),
    {ok, Res}.

input_pars_1(CallBackMod) when is_atom(CallBackMod)->
    erlang:apply(CallBackMod, input_pars, []);
input_pars_1(CallBackMod) when is_list(CallBackMod)->
    erlang:apply(list_to_atom(CallBackMod), input_pars, []);
input_pars_1(_) ->
    throw:error(badarg).
 
