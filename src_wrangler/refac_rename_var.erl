%% Copyright (c) 2009, Huiqing Li, Simon Thompson
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
%% =====================================================================
%% Refactoring: Rename a variable name.
%%
%% Author contact: hl@kent.ac.uk, sjt@kent.ac.uk
%%
%% =====================================================================
%%
%% @doc Rename a variable with a user-supplied new variable name.
%% <p> To apply this refactoring, point the cursor to the beginning of any occurrence of this variable, then select
%% <em> Rename Variable Name </em> from the <em> Refactor </em> menu, after that the refactorer will prompt to enter
%% the new parameter name in the mini-buffer.
%% </p>
%% <p> This refactoring has a local effect, i.e., it only affects the function in which the refactoring is initialised.
%% </p>
%% <p> The following <em> side-conditions </em> apply to this refactoring:
%% <li> The new variable name should not conflict with any of the declared variable names in the same scope;</li>
%% <li> The new name should not shadow any of the existing variables in the outer scopes, or be shadowed by any of
%% of existing variables in the inner scopes, i.e., renaming to the new name should not change the semantics of the
%% program.</li>
%% </p>
%% @end


-module(refac_rename_var).

-export([rename_var/6, rename_var_eclipse/6]).

-include("../include/wrangler.hrl").

%%-spec(rename_var/6::(filename(), integer(), integer(), string(), [dir()], integer()) ->
%%	     {error, string()} | {ok, string()}).
rename_var(FName, Line, Col, NewName, SearchPaths, TabWidth) ->
    rename_var(FName, Line, Col, NewName, SearchPaths, TabWidth, emacs).

%%-spec(rename_var_eclipse/6::(filename(), integer(), integer(), string(), [dir()], integer()) ->
%%	     {error, string()} | {ok, [{filename(), filename(), string()}]}).
rename_var_eclipse(FName, Line, Col, NewName, SearchPaths, TabWidth) ->
    rename_var(FName, Line, Col, NewName, SearchPaths, TabWidth, eclipse).

rename_var(FName, Line, Col, NewName, SearchPaths, TabWidth, Editor) ->
    ?wrangler_io("\nCMD: ~p:rename_var(~p, ~p, ~p, ~p, ~p, ~p).\n", 
		 [?MODULE,FName, Line, Col, NewName, SearchPaths, TabWidth]),
    case refac_util:is_var_name(NewName) of
	true -> ok;
	false -> throw({error, "Invalid new variable name."})
    end,
    NewName1 = list_to_atom(NewName), 
    {ok, {AnnAST1, _Info1}}= refac_util:parse_annotate_file(FName, true, SearchPaths, TabWidth),  
    case refac_util:pos_to_var_name(AnnAST1, {Line, Col}) of
	{ok, {VarName, DefinePos, C}} ->
	    {VarName, DefinePos, C};
	{error, _}-> 
	    throw({error, "You have not selected a variable name, "
		   "or the variable selected does not belong to "
		   "a syntactically well-formed function!"}),
	    {VarName, DefinePos, C} ={none, none, none}
    end,
    if DefinePos == [{0, 0}] -> 
	    case C of 
		macro_name ->
		    throw({error, "Renaming of a macro name is not supported by this refactoring!"});
		_ -> 
		    throw({error, "Renaming of a free variable is not supported by this refactoring!"})
	    end;				
       true -> ok
    end,
    if VarName /= NewName1 ->
	    case C of
		macro_name ->
		    throw({error, "Renaming of macro names is not supported yet."});
		_ -> ok
	    end, 
	    Form = pos_to_form(AnnAST1, {Line, Col}), 
	    Res = cond_check(Form, DefinePos, VarName, NewName1),
	    case Res of
		{true, _, _} ->
		    throw({error, "The new name is already declared in the same scope."});
		{_, true,_} -> 
		    throw({error, "The new name could cause name shadowing."});
		{_, _, true} -> 
		    throw({error, "The new name could change the "
			   "existing binding structure of variables."});
		_ -> ok
	    end,
	    {AnnAST2, _Changed} = rename(AnnAST1, DefinePos, NewName1),
	    case Editor of 
		emacs ->
		    refac_util:write_refactored_files_for_preview([{{FName, FName}, AnnAST2}]),
		    {ok, [FName]};
		eclipse ->
		    Content = refac_prettypr:print_ast(refac_util:file_format(FName),AnnAST2),
		    {ok, [{FName, FName,Content}]}
	    end;
       true ->
	    case Editor of 
		emacs ->
		    {ok, []};
		_ ->
		    Content = refac_prettypr:print_ast(refac_util:file_format(FName),AnnAST1),
		    {ok, [{FName, FName, Content}]}
	    end
    end.


%% =====================================================================
%% @spec cond_check(Tree::syntaxTree(), Pos::{integer(),integer()}, NewName::string())-> term()
%%   		
cond_check(Form, Pos, VarName,  NewName) ->
    Env_Bd_Fr_Vars = envs_bounds_frees(Form),
    BdVars = [B || {_, B, _}<-Env_Bd_Fr_Vars],
    %% The new name clashes with existing bound variables.
    F = fun({bound, Bds}) ->
		{Names, Poss} = lists:unzip(Bds),
		case lists:any(fun(P) -> lists:member(P, Poss) end, Pos)
		    andalso lists:member(NewName, Names) of 
		    false -> 
			false;
		    true -> 
			DefPoss = [P||{N, P} <- Bds, NewName==N],
			VarEnvs = [defpos_to_var_env(Form, [P])|| P<-DefPoss],
			VarToRenameEnv = defpos_to_var_env(Form, Pos),
			case lists:any(fun({N,_P}) ->N==NewName end, VarToRenameEnv) of 
			    true ->
				true;
			    false ->
				lists:any(fun(E) -> lists:any(fun({N,_P})-> N==VarName end, E) 
					  end, VarEnvs)
			end
		end	      
	end,
    Clash = lists:any(F, BdVars),
    %% The new name will shadow an existing free variable within the scope.
    Shadow1 = lists:any(fun ({{env, _}, {bound, Bds}, {free, Fs}}) ->
				Poss = [P || {_, P}<-Bds],
				Names = [N|| {N, _}<-Fs],
				F_Member = fun (P) -> lists:member(P, Poss) end,
				lists:any(F_Member, Pos) and lists:member(NewName, Names)
			end,
			Env_Bd_Fr_Vars),
    %% The new name will be shadowed by an existing bound variable.
    Shadow2 = lists:any(fun ({{env, _}, {bound, Bds}, {free, Fs}}) ->
				Poss = [P || {_, P} <-Fs],
				Names =[N||{N, _} <-Bds],
				F_Member = fun (P) -> lists:member(P, Poss) end,
				lists:any(F_Member, Pos) and lists:member(NewName, Names)
			end,
			Env_Bd_Fr_Vars),
    BindingChange1 = lists:any(fun({{env, Envs}, {bound, Bds},{free, _Fs}})->
				       Poss = [P||{_, P}<-Bds],
				       Names =[N||{N, _} <-Envs],
				       F_Member = fun (P) -> lists:member(P,Poss) end,
				       lists:any(F_Member, Pos) and lists:member(NewName, Names)
			       end, Env_Bd_Fr_Vars),
    BindingChange2 = lists:any(fun({{env, Envs}, {bound, Bds}, {free, _Fs}})->
				       Poss = [P||{_, P}<-Envs],
				       Names =[N||{N, _}<-Bds],
				       F_Member = fun (P) -> lists:member(P,Poss) end,
				       lists:any(F_Member, Pos) and lists:member(NewName, Names)
			       end, Env_Bd_Fr_Vars),
    {Clash, Shadow1 or Shadow2, BindingChange1 or BindingChange2}.


defpos_to_var_env(Node, DefPos) ->
    case refac_util:once_tdTU(fun defpos_to_var/2, Node, DefPos) of
	{_, false} ->
	    throw({error, "Refactoring failed because of a Wrangerl error."});
	{R, true} -> 
	    As = refac_syntax:get_ann(R),
	    case lists:keysearch(env, 1, As) of
		{value, {env, Env}} ->
		    Env;
		_ -> []
	    end
    end.
defpos_to_var(Node, DefPos) ->
    case refac_syntax:type(Node) of
	variable ->
	    Pos = refac_syntax:get_pos(Node),
	    case lists:member(Pos, DefPos) of
		true ->
		    {Node, true};
		_ -> {[],false}
	    end;
	_ -> {[], false}
    end.
    
    
pos_to_form(Node, Pos) ->
    case refac_util:once_tdTU(fun pos_to_form_1/2, Node, Pos) of
	{_, false} -> throw({error, "Refactoring failed because of a Wrangler error."});
	{R, true} -> R
    end.

pos_to_form_1(Node, Pos) ->
    case (refac_syntax:type(Node)==function) 
	orelse (refac_syntax:type(Node)==attribute) of
	true ->
	    {S, E} = refac_util:get_range(Node),
	    if (S =< Pos) and (Pos =< E) ->
		    {Node, true};
	       true -> {[], false}
	    end;
	_ -> {[], false}
    end.



%% =====================================================================
%% @spec rename(Tree::syntaxTree(), DefinePos::{integer(),integer()}, NewName::string())-> term()
%%

%%-spec(rename/3::(syntaxTree(), [{integer(), integer()}], atom()) ->
%%	     {syntaxTree(), bool()}).
rename(Tree, DefinePos, NewName) ->
    refac_util:stop_tdTP(fun do_rename/2, Tree, {DefinePos, NewName}).

%% =====================================================================
%%

do_rename(Tree, {DefinePos, NewName}) ->
    case refac_syntax:type(Tree) of
      variable ->
	  As = refac_syntax:get_ann(Tree),
	  case lists:keysearch(def, 1, As) of
	    {value, {def, DefinePos}} -> 
		  {refac_syntax:set_name(Tree, NewName), true};
	      _ -> {Tree, false}
	  end;
	_ -> {Tree, false}
    end.


%% =====================================================================
%% @spec envs_bounds_frees(Node::syntaxTree())-> {value, [{Key, [atom()}]}
%%       Key = env | bound | free
%% @doc Return the input environment of the subtree, the variables that are
%% bound as well as the variables that are free in the subtree.
envs_bounds_frees(Node) ->
    F = fun (T, B) ->
		As = refac_syntax:get_ann(T),
		EnVars = case lists:keysearch(env, 1, As) of
			     {value, {env, EnVars1}} -> EnVars1;
			     _ -> []
			 end,
		BdVars = case lists:keysearch(bound, 1, As) of
			     {value, {bound, BdVars1}} -> BdVars1;
			     _ -> []
			 end,
		FrVars = case lists:keysearch(free, 1, As) of
			     {value, {free, FrVars1}} -> FrVars1;
			     _ -> []
			 end,
		case (EnVars == []) and (BdVars == []) and (FrVars == []) of
		    true -> B;
		    _ -> [{{env, EnVars}, {bound, BdVars}, {free, FrVars}} | B]
		end
	end,
    lists:usort(refac_syntax_lib:fold(F, [], Node)).