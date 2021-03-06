(* Arities matter for the minus slice, but not for the plus slice. *)

(* + only allowed on code in a nest (in_nest = true).  ? only allowed on
rule_elems, and on subterms if the context is ? also. *)

module Ast0 = Ast0_cocci
module Ast = Ast_cocci
module V0 = Visitor_ast0
module V = Visitor_ast

let unitary = Type_cocci.Unitary

let ctr = ref 0
let get_ctr _ =
  let c = !ctr in
  ctr := !ctr + 1;
  c

(* --------------------------------------------------------------------- *)
(* Move plus tokens from the MINUS and CONTEXT structured nodes to the
corresponding leftmost and rightmost mcodes *)

let inline_mcodes =
  let bind x y = () in
  let option_default = () in
  let mcode _ = () in
  let do_nothing r k e =
    k e;
    let einfo = Ast0.get_info e in
    match (Ast0.get_mcodekind e) with
      Ast0.MINUS(replacements) ->
	(match !replacements with
	  ([],_) -> ()
	| replacements ->
	    let minus_try = function
		(true,mc) ->
		  if List.for_all
		      (function
			  Ast0.MINUS(mreplacements) -> true | _ -> false)
		      mc
		  then
		    (List.iter
		       (function
			   Ast0.MINUS(mreplacements) ->
			     mreplacements := replacements
			 | _ -> ())
		       mc;
		     true)
		  else false
	      | _ -> false in
	    if not (minus_try(einfo.Ast0.attachable_start,
			      einfo.Ast0.mcode_start)
		      or
    		    minus_try(einfo.Ast0.attachable_end,
			      einfo.Ast0.mcode_end))
	    then
	      failwith "minus tree should not have bad code on both sides")
    | Ast0.CONTEXT(befaft)
    | Ast0.MIXED(befaft) ->
	let concat starter startinfo ender endinfo =
	  let lst =
	    match (starter,ender) with
	      ([],_) -> ender
	    | (_,[]) -> starter
	    | _ ->
		if startinfo.Ast0.tline_end = endinfo.Ast0.tline_start
		then (* put them in the same inner list *)
		  let last = List.hd (List.rev starter) in
		  let butlast = List.rev(List.tl(List.rev starter)) in
		  butlast @ (last@(List.hd ender)) :: (List.tl ender)
		else starter @ ender in
	  (lst,
	   {endinfo with Ast0.tline_start = startinfo.Ast0.tline_start}) in
	let attach_bef bef beforeinfo = function
	    (true,mcl) ->
	      List.iter
		(function
		    Ast0.MINUS(mreplacements) ->
		      let (mrepl,tokeninfo) = !mreplacements in
		      mreplacements := concat bef beforeinfo mrepl tokeninfo
		  | Ast0.CONTEXT(mbefaft) ->
		      (match !mbefaft with
			(Ast.BEFORE(mbef),mbeforeinfo,a) ->
			  let (newbef,newinfo) =
			    concat bef beforeinfo mbef mbeforeinfo in
			  mbefaft := (Ast.BEFORE(newbef),newinfo,a)
		      | (Ast.AFTER(maft),_,a) ->
			  mbefaft :=
			    (Ast.BEFOREAFTER(bef,maft),beforeinfo,a)
		      | (Ast.BEFOREAFTER(mbef,maft),mbeforeinfo,a) ->
			  let (newbef,newinfo) =
			    concat bef beforeinfo mbef mbeforeinfo in
			  mbefaft :=
			    (Ast.BEFOREAFTER(newbef,maft),newinfo,a)
		      | (Ast.NOTHING,_,a) ->
			  mbefaft := (Ast.BEFORE(bef),beforeinfo,a))
		  |	_ -> failwith "unexpected annotation")
		mcl
	  | _ ->
	      failwith
		"context tree should not have bad code on both sides" in
	let attach_aft aft afterinfo = function
	    (true,mcl) ->
	      List.iter
		(function
		    Ast0.MINUS(mreplacements) ->
		      let (mrepl,tokeninfo) = !mreplacements in
		      mreplacements := concat mrepl tokeninfo aft afterinfo
		  | Ast0.CONTEXT(mbefaft) ->
		      (match !mbefaft with
			(Ast.BEFORE(mbef),b,_) ->
			  mbefaft :=
			    (Ast.BEFOREAFTER(mbef,aft),b,afterinfo)
		      | (Ast.AFTER(maft),b,mafterinfo) ->
			  let (newaft,newinfo) =
			    concat maft mafterinfo aft afterinfo in
			  mbefaft := (Ast.AFTER(newaft),b,newinfo)
		      | (Ast.BEFOREAFTER(mbef,maft),b,mafterinfo) ->
			  let (newaft,newinfo) =
			    concat maft mafterinfo aft afterinfo in
			  mbefaft :=
			    (Ast.BEFOREAFTER(mbef,newaft),b,newinfo)
		      | (Ast.NOTHING,b,_) ->
			  mbefaft := (Ast.AFTER(aft),b,afterinfo))
		  |	_ -> failwith "unexpected annotation")
		mcl
	  | _ ->
	      failwith
		"context tree should not have bad code on both sides" in
	(match !befaft with
	  (Ast.BEFORE(bef),beforeinfo,_) ->
	    attach_bef bef beforeinfo
	      (einfo.Ast0.attachable_start,einfo.Ast0.mcode_start)
	| (Ast.AFTER(aft),_,afterinfo) ->
	    attach_aft aft afterinfo
	      (einfo.Ast0.attachable_end,einfo.Ast0.mcode_end)
	| (Ast.BEFOREAFTER(bef,aft),beforeinfo,afterinfo) ->
	    attach_bef bef beforeinfo
	      (einfo.Ast0.attachable_start,einfo.Ast0.mcode_start);
	    attach_aft aft afterinfo
	      (einfo.Ast0.attachable_end,einfo.Ast0.mcode_end)
	| (Ast.NOTHING,_,_) -> ())
    | Ast0.PLUS -> () in
  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode mcode
    do_nothing do_nothing do_nothing do_nothing do_nothing do_nothing
    do_nothing do_nothing do_nothing do_nothing do_nothing do_nothing
    do_nothing do_nothing do_nothing

(* --------------------------------------------------------------------- *)
(* For function declarations.  Can't use the mcode at the root, because that
might be mixed when the function contains ()s, where agglomeration of -s is
not possible. *)

let check_allminus =
  let donothing r k e = k e in
  let bind x y = x && y in
  let option_default = true in
  let mcode (_,_,_,mc,_) =
    match mc with
      Ast0.MINUS(r) -> let (plusses,_) = !r in plusses = []
    | _ -> false in

  (* special case for disj *)
  let expression r k e =
    match Ast0.unwrap e with
      Ast0.DisjExpr(starter,expr_list,mids,ender) ->
	List.for_all r.V0.combiner_expression expr_list
    | _ -> k e in

  let declaration r k e =
    match Ast0.unwrap e with
      Ast0.DisjDecl(starter,decls,mids,ender) ->
	List.for_all r.V0.combiner_declaration decls
    | _ -> k e in

  let typeC r k e =
    match Ast0.unwrap e with
      Ast0.DisjType(starter,decls,mids,ender) ->
	List.for_all r.V0.combiner_typeC decls
    | _ -> k e in

  let statement r k e =
    match Ast0.unwrap e with
      Ast0.Disj(starter,statement_dots_list,mids,ender) ->
	List.for_all r.V0.combiner_statement_dots statement_dots_list
    | _ -> k e in

  V0.combiner bind option_default
    mcode mcode mcode mcode mcode mcode mcode mcode mcode mcode
    mcode mcode
    donothing donothing donothing donothing donothing donothing
    donothing expression typeC donothing donothing declaration
    statement donothing donothing

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)

let get_option fn = function
    None -> None
  | Some x -> Some (fn x)

(* --------------------------------------------------------------------- *)
(* --------------------------------------------------------------------- *)
(* Mcode *)

let convert_info info =
  let strings_to_s l =
    List.map
      (function (s,info) -> (s,info.Ast0.line_start,info.Ast0.column))
      l in
  { Ast.line = info.Ast0.pos_info.Ast0.line_start;
    Ast.column = info.Ast0.pos_info.Ast0.column;
    Ast.strbef = strings_to_s info.Ast0.strings_before;
    Ast.straft = strings_to_s info.Ast0.strings_after; }

let convert_mcodekind = function
    Ast0.MINUS(replacements) ->
      let (replacements,_) = !replacements in
      Ast.MINUS(Ast.NoPos,replacements)
  | Ast0.PLUS -> Ast.PLUS
  | Ast0.CONTEXT(befaft) ->
      let (befaft,_,_) = !befaft in Ast.CONTEXT(Ast.NoPos,befaft)
  | Ast0.MIXED(_) -> failwith "not possible for mcode"

let pos_mcode(term,_,info,mcodekind,pos) =
  (* avoids a recursion problem *)
  (term,convert_info info,convert_mcodekind mcodekind,Ast.NoMetaPos)

let mcode(term,_,info,mcodekind,pos) =
  let pos =
    match !pos with
      Ast0.MetaPos(pos,constraints,per) ->
	Ast.MetaPos(pos_mcode pos,constraints,per,unitary,false)
    | _ -> Ast.NoMetaPos in
  (term,convert_info info,convert_mcodekind mcodekind,pos)

(* --------------------------------------------------------------------- *)
(* Dots *)
let wrap ast line isos =
  {(Ast.make_term ast) with Ast.node_line = line;
    Ast.iso_info = isos}

let rewrap ast0 isos ast =
  wrap ast ((Ast0.get_info ast0).Ast0.pos_info.Ast0.line_start) isos

let no_isos = []

(* no isos on tokens *)
let tokenwrap (_,info,_,_) s ast = wrap ast info.Ast.line no_isos
let iso_tokenwrap (_,info,_,_) s ast iso = wrap ast info.Ast.line iso

let dots fn d =
  rewrap d no_isos
    (match Ast0.unwrap d with
      Ast0.DOTS(x) -> Ast.DOTS(List.map fn x)
    | Ast0.CIRCLES(x) -> Ast.CIRCLES(List.map fn x)
    | Ast0.STARS(x) -> Ast.STARS(List.map fn x))

(* --------------------------------------------------------------------- *)
(* Identifier *)

let rec do_isos l = List.map (function (nm,x) -> (nm,anything x)) l

and ident i =
  rewrap i (do_isos (Ast0.get_iso i))
    (match Ast0.unwrap i with
      Ast0.Id(name) -> Ast.Id(mcode name)
    | Ast0.MetaId(name,constraints,_) ->
	let constraints = List.map ident constraints in
	Ast.MetaId(mcode name,constraints,unitary,false)
    | Ast0.MetaFunc(name,constraints,_) ->
	let constraints = List.map ident constraints in
	Ast.MetaFunc(mcode name,constraints,unitary,false)
    | Ast0.MetaLocalFunc(name,constraints,_) ->
	let constraints = List.map ident constraints in
	Ast.MetaLocalFunc(mcode name,constraints,unitary,false)
    | Ast0.OptIdent(id) -> Ast.OptIdent(ident id)
    | Ast0.UniqueIdent(id) -> Ast.UniqueIdent(ident id))

(* --------------------------------------------------------------------- *)
(* Expression *)

and expression e =
  let e1 =
  rewrap e (do_isos (Ast0.get_iso e))
    (match Ast0.unwrap e with
      Ast0.Ident(id) -> Ast.Ident(ident id)
    | Ast0.Constant(const) ->
	Ast.Constant(mcode const)
    | Ast0.FunCall(fn,lp,args,rp) ->
	let fn = expression fn in
	let lp = mcode lp in
	let args = dots expression args in
	let rp = mcode rp in
	Ast.FunCall(fn,lp,args,rp)
    | Ast0.Assignment(left,op,right,simple) ->
	Ast.Assignment(expression left,mcode op,expression right,simple)
    | Ast0.CondExpr(exp1,why,exp2,colon,exp3) ->
	let exp1 = expression exp1 in
	let why = mcode why in
	let exp2 = get_option expression exp2 in
	let colon = mcode colon in
	let exp3 = expression exp3 in
	Ast.CondExpr(exp1,why,exp2,colon,exp3)
    | Ast0.Postfix(exp,op) ->
	Ast.Postfix(expression exp,mcode op)
    | Ast0.Infix(exp,op) ->
	Ast.Infix(expression exp,mcode op)
    | Ast0.Unary(exp,op) ->
	Ast.Unary(expression exp,mcode op)
    | Ast0.Binary(left,op,right) ->
	Ast.Binary(expression left,mcode op,expression right)
    | Ast0.Nested(left,op,right) ->
	Ast.Nested(expression left,mcode op,expression right)
    | Ast0.Paren(lp,exp,rp) ->
	Ast.Paren(mcode lp,expression exp,mcode rp)
    | Ast0.ArrayAccess(exp1,lb,exp2,rb) ->
	Ast.ArrayAccess(expression exp1,mcode lb,expression exp2,mcode rb)
    | Ast0.RecordAccess(exp,pt,field) ->
	Ast.RecordAccess(expression exp,mcode pt,ident field)
    | Ast0.RecordPtAccess(exp,ar,field) ->
	Ast.RecordPtAccess(expression exp,mcode ar,ident field)
    | Ast0.Cast(lp,ty,rp,exp) ->
	Ast.Cast(mcode lp,typeC ty,mcode rp,expression exp)
    | Ast0.SizeOfExpr(szf,exp) ->
	Ast.SizeOfExpr(mcode szf,expression exp)
    | Ast0.SizeOfType(szf,lp,ty,rp) ->
	Ast.SizeOfType(mcode szf, mcode lp,typeC ty,mcode rp)
    | Ast0.TypeExp(ty) -> Ast.TypeExp(typeC ty)
    | Ast0.MetaErr(name,constraints,_)  ->
	let constraints = List.map expression constraints in
	Ast.MetaErr(mcode name,constraints,unitary,false)
    | Ast0.MetaExpr(name,constraints,ty,form,_)  ->
	let constraints = List.map expression constraints in
	Ast.MetaExpr(mcode name,constraints,unitary,ty,form,false)
    | Ast0.MetaExprList(name,Some lenname,_) ->
	Ast.MetaExprList(mcode name,Some (mcode lenname,unitary,false),
			 unitary,false)
    | Ast0.MetaExprList(name,None,_) ->
	Ast.MetaExprList(mcode name,None,unitary,false)
    | Ast0.EComma(cm)         -> Ast.EComma(mcode cm)
    | Ast0.DisjExpr(_,exps,_,_)     -> Ast.DisjExpr(List.map expression exps)
    | Ast0.NestExpr(_,exp_dots,_,whencode,multi) ->
	let whencode = get_option expression whencode in
	Ast.NestExpr(dots expression exp_dots,whencode,multi)
    | Ast0.Edots(dots,whencode) ->
	let dots = mcode dots in
	let whencode = get_option expression whencode in
	Ast.Edots(dots,whencode)
    | Ast0.Ecircles(dots,whencode) ->
	let dots = mcode dots in
	let whencode = get_option expression whencode in
	Ast.Ecircles(dots,whencode)
    | Ast0.Estars(dots,whencode) ->
	let dots = mcode dots in
	let whencode = get_option expression whencode in
	Ast.Estars(dots,whencode)
    | Ast0.OptExp(exp) -> Ast.OptExp(expression exp)
    | Ast0.UniqueExp(exp) -> Ast.UniqueExp(expression exp)) in
  if Ast0.get_test_exp e then Ast.set_test_exp e1 else e1

and expression_dots ed = dots expression ed

(* --------------------------------------------------------------------- *)
(* Types *)

and rewrap_iso t t1 = rewrap t (do_isos (Ast0.get_iso t)) t1

and typeC t =
  rewrap t (do_isos (Ast0.get_iso t))
    (match Ast0.unwrap t with
      Ast0.ConstVol(cv,ty) ->
	let rec collect_disjs t =
	  match Ast0.unwrap t with
	    Ast0.DisjType(_,types,_,_) ->
	      if Ast0.get_iso t = []
	      then List.concat (List.map collect_disjs types)
	      else failwith "unexpected iso on a disjtype"
	  | _ -> [t] in
	let res =
	  List.map
	    (function ty ->
	      Ast.Type
		(Some (mcode cv),rewrap_iso ty (base_typeC ty)))
	    (collect_disjs ty) in
	(* one could worry that isos are lost because we flatten the
	   disjunctions.  but there should not be isos on the disjunctions
	   themselves. *)
	(match res with
	  [ty] -> ty
	| types -> Ast.DisjType(List.map (rewrap t no_isos) types))
    | Ast0.BaseType(_) | Ast0.Signed(_,_) | Ast0.Pointer(_,_)
    | Ast0.FunctionPointer(_,_,_,_,_,_,_) | Ast0.FunctionType(_,_,_,_)
    | Ast0.Array(_,_,_,_) | Ast0.EnumName(_,_) | Ast0.StructUnionName(_,_)
    | Ast0.StructUnionDef(_,_,_,_) | Ast0.TypeName(_) | Ast0.MetaType(_,_) ->
	Ast.Type(None,rewrap t no_isos (base_typeC t))
    | Ast0.DisjType(_,types,_,_) -> Ast.DisjType(List.map typeC types)
    | Ast0.OptType(ty) -> Ast.OptType(typeC ty)
    | Ast0.UniqueType(ty) -> Ast.UniqueType(typeC ty))

and base_typeC t =
  match Ast0.unwrap t with
    Ast0.BaseType(ty,strings) -> Ast.BaseType(ty,List.map mcode strings)
  | Ast0.Signed(sgn,ty) ->
      Ast.SignedT(mcode sgn,
		  get_option (function x -> rewrap_iso x (base_typeC x)) ty)
  | Ast0.Pointer(ty,star) -> Ast.Pointer(typeC ty,mcode star)
  | Ast0.FunctionPointer(ty,lp1,star,rp1,lp2,params,rp2) ->
      Ast.FunctionPointer
	(typeC ty,mcode lp1,mcode star,mcode rp1,
	 mcode lp2,parameter_list params,mcode rp2)
  | Ast0.FunctionType(ret,lp,params,rp) ->
      let allminus = check_allminus.V0.combiner_typeC t in
      Ast.FunctionType
	(allminus,get_option typeC ret,mcode lp,
	 parameter_list params,mcode rp)
  | Ast0.Array(ty,lb,size,rb) ->
      Ast.Array(typeC ty,mcode lb,get_option expression size,mcode rb)
  | Ast0.EnumName(kind,name) ->
      Ast.EnumName(mcode kind,ident name)
  | Ast0.StructUnionName(kind,name) ->
      Ast.StructUnionName(mcode kind,get_option ident name)
  | Ast0.StructUnionDef(ty,lb,decls,rb) ->
      Ast.StructUnionDef(typeC ty,mcode lb,
			 dots declaration decls,
			 mcode rb)
  | Ast0.TypeName(name) -> Ast.TypeName(mcode name)
  | Ast0.MetaType(name,_) ->
      Ast.MetaType(mcode name,unitary,false)
  | _ -> failwith "ast0toast: unexpected type"

(* --------------------------------------------------------------------- *)
(* Variable declaration *)
(* Even if the Cocci program specifies a list of declarations, they are
   split out into multiple declarations of a single variable each. *)

and declaration d =
  rewrap d (do_isos (Ast0.get_iso d))
    (match Ast0.unwrap d with
      Ast0.Init(stg,ty,id,eq,ini,sem) ->
	let stg = get_option mcode stg in
	let ty = typeC ty in
	let id = ident id in
	let eq = mcode eq in
	let ini = initialiser ini in
	let sem = mcode sem in
	Ast.Init(stg,ty,id,eq,ini,sem)
    | Ast0.UnInit(stg,ty,id,sem) ->
	(match Ast0.unwrap ty with
	  Ast0.FunctionType(tyx,lp1,params,rp1) ->
	    let allminus = check_allminus.V0.combiner_declaration d in
	    Ast.UnInit(get_option mcode stg,
		       rewrap ty (do_isos (Ast0.get_iso ty))
			 (Ast.Type
			    (None,
			     rewrap ty no_isos
			       (Ast.FunctionType
				  (allminus,get_option typeC tyx,mcode lp1,
				   parameter_list params,mcode rp1)))),
		       ident id,mcode sem)
	| _ -> Ast.UnInit(get_option mcode stg,typeC ty,ident id,mcode sem))
    | Ast0.MacroDecl(name,lp,args,rp,sem) ->
	let name = ident name in
	let lp = mcode lp in
	let args = dots expression args in
	let rp = mcode rp in
	let sem = mcode sem in
	Ast.MacroDecl(name,lp,args,rp,sem)
    | Ast0.TyDecl(ty,sem) -> Ast.TyDecl(typeC ty,mcode sem)
    | Ast0.Typedef(stg,ty,id,sem) ->
	let id = typeC id in
	(match Ast.unwrap id with
	  Ast.Type(None,id) -> (* only MetaType or Id *)
	    Ast.Typedef(mcode stg,typeC ty,id,mcode sem)
	| _ -> failwith "bad typedef")
    | Ast0.DisjDecl(_,decls,_,_) -> Ast.DisjDecl(List.map declaration decls)
    | Ast0.Ddots(dots,whencode) ->
	let dots = mcode dots in
	let whencode = get_option declaration whencode in
	Ast.Ddots(dots,whencode)
    | Ast0.OptDecl(decl) -> Ast.OptDecl(declaration decl)
    | Ast0.UniqueDecl(decl) -> Ast.UniqueDecl(declaration decl))

and declaration_dots l = dots declaration l

(* --------------------------------------------------------------------- *)
(* Initialiser *)

and strip_idots initlist =
  match Ast0.unwrap initlist with
    Ast0.DOTS(x) ->
      let (whencode,init) =
	List.fold_left
	  (function (prevwhen,previnit) ->
	    function cur ->
	      match Ast0.unwrap cur with
		Ast0.Idots(dots,Some whencode) ->
		  (whencode :: prevwhen, previnit)
	      | Ast0.Idots(dots,None) -> (prevwhen,previnit)
	      | _ -> (prevwhen, cur :: previnit))
	  ([],[]) x in
      (List.rev whencode, List.rev init)
  | Ast0.CIRCLES(x) | Ast0.STARS(x) -> failwith "not possible for an initlist"

and initialiser i =
  rewrap i no_isos
    (match Ast0.unwrap i with
      Ast0.MetaInit(name,_) -> Ast.MetaInit(mcode name,unitary,false)
    | Ast0.InitExpr(exp) -> Ast.InitExpr(expression exp)
    | Ast0.InitList(lb,initlist,rb) ->
	let (whencode,initlist) =  strip_idots initlist in
	Ast.InitList(mcode lb,List.map initialiser initlist,mcode rb,
		     List.map initialiser whencode)
    | Ast0.InitGccExt(designators,eq,ini) ->
	Ast.InitGccExt(List.map designator designators,mcode eq,
		       initialiser ini)
    | Ast0.InitGccName(name,eq,ini) ->
	Ast.InitGccName(ident name,mcode eq,initialiser ini)
    | Ast0.IComma(comma) -> Ast.IComma(mcode comma)
    | Ast0.Idots(_,_) -> failwith "Idots should have been removed"
    | Ast0.OptIni(ini) -> Ast.OptIni(initialiser ini)
    | Ast0.UniqueIni(ini) -> Ast.UniqueIni(initialiser ini))

and designator = function
    Ast0.DesignatorField(dot,id) -> Ast.DesignatorField(mcode dot,ident id)
  | Ast0.DesignatorIndex(lb,exp,rb) ->
      Ast.DesignatorIndex(mcode lb, expression exp, mcode rb)
  | Ast0.DesignatorRange(lb,min,dots,max,rb) ->
      Ast.DesignatorRange(mcode lb,expression min,mcode dots,expression max,
			  mcode rb)

(* --------------------------------------------------------------------- *)
(* Parameter *)

and parameterTypeDef p =
  rewrap p no_isos
    (match Ast0.unwrap p with
      Ast0.VoidParam(ty) -> Ast.VoidParam(typeC ty)
    | Ast0.Param(ty,id) -> Ast.Param(typeC ty,get_option ident id)
    | Ast0.MetaParam(name,_) ->
	Ast.MetaParam(mcode name,unitary,false)
    | Ast0.MetaParamList(name,Some lenname,_) ->
	Ast.MetaParamList(mcode name,Some(mcode lenname,unitary,false),
			  unitary,false)
    | Ast0.MetaParamList(name,None,_) ->
	Ast.MetaParamList(mcode name,None,unitary,false)
    | Ast0.PComma(cm) -> Ast.PComma(mcode cm)
    | Ast0.Pdots(dots) -> Ast.Pdots(mcode dots)
    | Ast0.Pcircles(dots) -> Ast.Pcircles(mcode dots)
    | Ast0.OptParam(param) -> Ast.OptParam(parameterTypeDef param)
    | Ast0.UniqueParam(param) -> Ast.UniqueParam(parameterTypeDef param))

and parameter_list l = dots parameterTypeDef l

(* --------------------------------------------------------------------- *)
(* Top-level code *)

and statement s =
  let rec statement seqible s =
    let rewrap_stmt ast0 ast =
      let befaft =
	match Ast0.get_dots_bef_aft s with
	  Ast0.NoDots -> Ast.NoDots
	| Ast0.DroppingBetweenDots s ->
	    Ast.DroppingBetweenDots (statement seqible s,get_ctr())
	| Ast0.AddingBetweenDots s ->
	    Ast.AddingBetweenDots (statement seqible s,get_ctr()) in
      Ast.set_dots_bef_aft befaft (rewrap ast0 no_isos ast) in
    let rewrap_rule_elem ast0 ast =
      rewrap ast0 (do_isos (Ast0.get_iso ast0)) ast in
    rewrap_stmt s
      (match Ast0.unwrap s with
	Ast0.Decl((_,bef),decl) ->
	  Ast.Atomic(rewrap_rule_elem s
		       (Ast.Decl(convert_mcodekind bef,
				 check_allminus.V0.combiner_statement s,
				 declaration decl)))
      | Ast0.Seq(lbrace,body,rbrace) ->
	  let lbrace = mcode lbrace in
	  let (decls,body) = separate_decls seqible body in
	  let rbrace = mcode rbrace in
	  Ast.Seq(iso_tokenwrap lbrace s (Ast.SeqStart(lbrace))
		    (do_isos (Ast0.get_iso s)),
		  decls,body,
		  tokenwrap rbrace s (Ast.SeqEnd(rbrace)))
      | Ast0.ExprStatement(exp,sem) ->
	  Ast.Atomic(rewrap_rule_elem s
		       (Ast.ExprStatement(expression exp,mcode sem)))
      | Ast0.IfThen(iff,lp,exp,rp,branch,(_,aft)) ->
	  Ast.IfThen
	    (rewrap_rule_elem s
	       (Ast.IfHeader(mcode iff,mcode lp,expression exp,mcode rp)),
	     statement Ast.NotSequencible branch,
	     ([],[],[],convert_mcodekind aft))
      | Ast0.IfThenElse(iff,lp,exp,rp,branch1,els,branch2,(_,aft)) ->
	  let els = mcode els in
	  Ast.IfThenElse
	    (rewrap_rule_elem s
	       (Ast.IfHeader(mcode iff,mcode lp,expression exp,mcode rp)),
	     statement Ast.NotSequencible branch1,
	     tokenwrap els s (Ast.Else(els)),
	     statement Ast.NotSequencible branch2,
	     ([],[],[],convert_mcodekind aft))
      | Ast0.While(wh,lp,exp,rp,body,(_,aft)) ->
	  Ast.While(rewrap_rule_elem s
		      (Ast.WhileHeader
			 (mcode wh,mcode lp,expression exp,mcode rp)),
		    statement Ast.NotSequencible body,
		    ([],[],[],convert_mcodekind aft))
      | Ast0.Do(d,body,wh,lp,exp,rp,sem) ->
	  let wh = mcode wh in
	  Ast.Do(rewrap_rule_elem s (Ast.DoHeader(mcode d)),
		 statement Ast.NotSequencible body,
		 tokenwrap wh s
		   (Ast.WhileTail(wh,mcode lp,expression exp,mcode rp,
				  mcode sem)))
      | Ast0.For(fr,lp,exp1,sem1,exp2,sem2,exp3,rp,body,(_,aft)) ->
	  let fr = mcode fr in
	  let lp = mcode lp in
	  let exp1 = get_option expression exp1 in
	  let sem1 = mcode sem1 in
	  let exp2 = get_option expression exp2 in
	  let sem2= mcode sem2 in
	  let exp3 = get_option expression exp3 in
	  let rp = mcode rp in
	  let body = statement Ast.NotSequencible body in
	  Ast.For(rewrap_rule_elem s
		    (Ast.ForHeader(fr,lp,exp1,sem1,exp2,sem2,exp3,rp)),
		  body,([],[],[],convert_mcodekind aft))
      | Ast0.Iterator(nm,lp,args,rp,body,(_,aft)) ->
	  Ast.Iterator(rewrap_rule_elem s
		      (Ast.IteratorHeader
			 (ident nm,mcode lp,
			  dots expression args,
			  mcode rp)),
		    statement Ast.NotSequencible body,
		    ([],[],[],convert_mcodekind aft))
      |	Ast0.Switch(switch,lp,exp,rp,lb,cases,rb) ->
	  let switch = mcode switch in
	  let lp = mcode lp in
	  let exp = expression exp in
	  let rp = mcode rp in
	  let lb = mcode lb in
	  let cases = List.map case_line (Ast0.undots cases) in
	  let rb = mcode rb in
	  Ast.Switch(rewrap_rule_elem s (Ast.SwitchHeader(switch,lp,exp,rp)),
		     tokenwrap lb s (Ast.SeqStart(lb)),
		     cases,
		     tokenwrap rb s (Ast.SeqEnd(rb)))
      | Ast0.Break(br,sem) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Break(mcode br,mcode sem)))
      | Ast0.Continue(cont,sem) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Continue(mcode cont,mcode sem)))
      |	Ast0.Label(l,dd) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Label(ident l,mcode dd)))
      |	Ast0.Goto(goto,l,sem) ->
	  Ast.Atomic
	    (rewrap_rule_elem s (Ast.Goto(mcode goto,ident l,mcode sem)))
      | Ast0.Return(ret,sem) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Return(mcode ret,mcode sem)))
      | Ast0.ReturnExpr(ret,exp,sem) ->
	  Ast.Atomic
	    (rewrap_rule_elem s
	       (Ast.ReturnExpr(mcode ret,expression exp,mcode sem)))
      | Ast0.MetaStmt(name,_) ->
	  Ast.Atomic(rewrap_rule_elem s
		       (Ast.MetaStmt(mcode name,unitary,seqible,false)))
      | Ast0.MetaStmtList(name,_) ->
	  Ast.Atomic(rewrap_rule_elem s
		       (Ast.MetaStmtList(mcode name,unitary,false)))
      | Ast0.TopExp(exp) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.TopExp(expression exp)))
      | Ast0.Exp(exp) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Exp(expression exp)))
      | Ast0.TopInit(init) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.TopInit(initialiser init)))
      | Ast0.Ty(ty) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Ty(typeC ty)))
      | Ast0.Disj(_,rule_elem_dots_list,_,_) ->
	  Ast.Disj(List.map (function x -> statement_dots seqible x)
		     rule_elem_dots_list)
      | Ast0.Nest(_,rule_elem_dots,_,whn,multi) ->
	  Ast.Nest
	    (statement_dots Ast.Sequencible rule_elem_dots,
	     List.map
	       (whencode (statement_dots Ast.Sequencible)
		 (statement Ast.NotSequencible))
	       whn,
	     multi,[],[])
      | Ast0.Dots(d,whn) ->
	  let d = mcode d in
	  let whn =
	    List.map
	      (whencode (statement_dots Ast.Sequencible)
		 (statement Ast.NotSequencible))
	      whn in
	  Ast.Dots(d,whn,[],[])
      | Ast0.Circles(d,whn) ->
	  let d = mcode d in
	  let whn =
	    List.map
	      (whencode (statement_dots Ast.Sequencible)
		 (statement Ast.NotSequencible))
	      whn in
	  Ast.Circles(d,whn,[],[])
      | Ast0.Stars(d,whn) ->
	  let d = mcode d in
	  let whn =
	    List.map
	      (whencode (statement_dots Ast.Sequencible)
		 (statement Ast.NotSequencible))
	      whn in
	  Ast.Stars(d,whn,[],[])
      | Ast0.FunDecl((_,bef),fi,name,lp,params,rp,lbrace,body,rbrace) ->
	  let fi = List.map fninfo fi in
	  let name = ident name in
	  let lp = mcode lp in
	  let params = parameter_list params in
	  let rp = mcode rp in
	  let lbrace = mcode lbrace in
	  let (decls,body) = separate_decls seqible body in
	  let rbrace = mcode rbrace in
	  let allminus = check_allminus.V0.combiner_statement s in
	  Ast.FunDecl(rewrap_rule_elem s
			(Ast.FunHeader(convert_mcodekind bef,
				       allminus,fi,name,lp,params,rp)),
		      tokenwrap lbrace s (Ast.SeqStart(lbrace)),
		      decls,body,
		      tokenwrap rbrace s (Ast.SeqEnd(rbrace)))
      |	Ast0.Include(inc,str) ->
	  Ast.Atomic(rewrap_rule_elem s (Ast.Include(mcode inc,mcode str)))
      | Ast0.Define(def,id,params,body) ->
	  Ast.Define
	    (rewrap_rule_elem s
	       (Ast.DefineHeader
		  (mcode def,ident id, define_parameters params)),
	     statement_dots Ast.NotSequencible (*not sure*) body)
      | Ast0.OptStm(stm) -> Ast.OptStm(statement seqible stm)
      | Ast0.UniqueStm(stm) -> Ast.UniqueStm(statement seqible stm))

  and define_parameters p =
    rewrap p no_isos
      (match Ast0.unwrap p with
	Ast0.NoParams -> Ast.NoParams
      | Ast0.DParams(lp,params,rp) ->
	  Ast.DParams(mcode lp,
		      dots define_param params,
		      mcode rp))

  and define_param p =
    rewrap p no_isos
      (match Ast0.unwrap p with
	Ast0.DParam(id) -> Ast.DParam(ident id)
      | Ast0.DPComma(comma) -> Ast.DPComma(mcode comma)
      | Ast0.DPdots(d) -> Ast.DPdots(mcode d)
      | Ast0.DPcircles(c) -> Ast.DPcircles(mcode c)
      | Ast0.OptDParam(dp) -> Ast.OptDParam(define_param dp)
      | Ast0.UniqueDParam(dp) -> Ast.UniqueDParam(define_param dp))

  and whencode notfn alwaysfn = function
      Ast0.WhenNot a -> Ast.WhenNot (notfn a)
    | Ast0.WhenAlways a -> Ast.WhenAlways (alwaysfn a)
    | Ast0.WhenModifier(x) -> Ast.WhenModifier(x)
    | x ->
	let rewrap_rule_elem ast0 ast =
	  rewrap ast0 (do_isos (Ast0.get_iso ast0)) ast in
	match x with
	  Ast0.WhenNotTrue(e) ->
	    Ast.WhenNotTrue(rewrap_rule_elem e (Ast.Exp(expression e)))
	| Ast0.WhenNotFalse(e) ->
	    Ast.WhenNotFalse(rewrap_rule_elem e (Ast.Exp(expression e)))
	| _ -> failwith "not possible"

  and process_list seqible isos = function
      [] -> []
    | x::rest ->
	let first = statement seqible x in
	let first =
	  if !Flag.track_iso_usage
	  then Ast.set_isos first (isos@(Ast.get_isos first))
	  else first in
	(match Ast0.unwrap x with
	  Ast0.Dots(_,_) | Ast0.Nest(_) ->
	    first::(process_list (Ast.SequencibleAfterDots []) no_isos rest)
	| _ ->
	    first::(process_list Ast.Sequencible no_isos rest))

  and statement_dots seqible d =
    let isos = do_isos (Ast0.get_iso d) in
    rewrap d no_isos
      (match Ast0.unwrap d with
	Ast0.DOTS(x) -> Ast.DOTS(process_list seqible isos x)
      | Ast0.CIRCLES(x) -> Ast.CIRCLES(process_list seqible isos x)
      | Ast0.STARS(x) -> Ast.STARS(process_list seqible isos x))

  and separate_decls seqible d =
    let rec collect_decls = function
	[] -> ([],[])
      | (x::xs) as l ->
	  (match Ast0.unwrap x with
	    Ast0.Decl(_) ->
	      let (decls,other) = collect_decls xs in
	      (x :: decls,other)
	  | Ast0.Dots(_,_) | Ast0.Nest(_,_,_,_,_) ->
	      let (decls,other) = collect_decls xs in
	      (match decls with
		[] -> ([],x::other)
	      | _ -> (x :: decls,other))
	  | Ast0.Disj(starter,stmt_dots_list,mids,ender) ->
	      let disjs = List.map collect_dot_decls stmt_dots_list in
	      let all_decls = List.for_all (function (_,s) -> s=[]) disjs in
	      if all_decls
	      then
		let (decls,other) = collect_decls xs in
		(x :: decls,other)
	      else ([],l)
	  | _ -> ([],l))

    and collect_dot_decls d =
      match Ast0.unwrap d with
	Ast0.DOTS(x) -> collect_decls x
      | Ast0.CIRCLES(x) -> collect_decls x
      | Ast0.STARS(x) -> collect_decls x in

    let process l d fn =
      let (decls,other) = collect_decls l in
      (rewrap d no_isos (fn (List.map (statement seqible) decls)),
       rewrap d no_isos
	 (fn (process_list seqible (do_isos (Ast0.get_iso d)) other))) in
    match Ast0.unwrap d with
      Ast0.DOTS(x) -> process x d (function x -> Ast.DOTS x)
    | Ast0.CIRCLES(x) -> process x d (function x -> Ast.CIRCLES x)
    | Ast0.STARS(x) -> process x d (function x -> Ast.STARS x) in

  statement Ast.Sequencible s

and fninfo = function
    Ast0.FStorage(stg) -> Ast.FStorage(mcode stg)
  | Ast0.FType(ty) -> Ast.FType(typeC ty)
  | Ast0.FInline(inline) -> Ast.FInline(mcode inline)
  | Ast0.FAttr(attr) -> Ast.FAttr(mcode attr)

and option_to_list = function
    Some x -> [x]
  | None -> []

and case_line c =
  rewrap c no_isos
    (match Ast0.unwrap c with
      Ast0.Default(def,colon,code) ->
	let def = mcode def in
	let colon = mcode colon in
	let code = dots statement code in
	Ast.CaseLine(rewrap c no_isos (Ast.Default(def,colon)),code)
    | Ast0.Case(case,exp,colon,code) ->
	let case = mcode case in
	let exp = expression exp in
	let colon = mcode colon in
	let code = dots statement code in
	Ast.CaseLine(rewrap c no_isos (Ast.Case(case,exp,colon)),code)
    | Ast0.OptCase(case) -> Ast.OptCase(case_line case))

and statement_dots l = dots statement l

(* --------------------------------------------------------------------- *)

(* what is possible is only what is at the top level in an iso *)
and anything = function
    Ast0.DotsExprTag(d) -> Ast.ExprDotsTag(expression_dots d)
  | Ast0.DotsParamTag(d) -> Ast.ParamDotsTag(parameter_list d)
  | Ast0.DotsInitTag(d) -> failwith "not possible"
  | Ast0.DotsStmtTag(d) -> Ast.StmtDotsTag(statement_dots d)
  | Ast0.DotsDeclTag(d) -> Ast.DeclDotsTag(declaration_dots d)
  | Ast0.DotsCaseTag(d) -> failwith "not possible"
  | Ast0.IdentTag(d) -> Ast.IdentTag(ident d)
  | Ast0.ExprTag(d) -> Ast.ExpressionTag(expression d)
  | Ast0.ArgExprTag(d) | Ast0.TestExprTag(d) ->
     failwith "only in isos, not converted to ast"
  | Ast0.TypeCTag(d) -> Ast.FullTypeTag(typeC d)
  | Ast0.ParamTag(d) -> Ast.ParamTag(parameterTypeDef d)
  | Ast0.InitTag(d) -> Ast.InitTag(initialiser d)
  | Ast0.DeclTag(d) -> Ast.DeclarationTag(declaration d)
  | Ast0.StmtTag(d) -> Ast.StatementTag(statement d)
  | Ast0.CaseLineTag(d) -> Ast.CaseLineTag(case_line d)
  | Ast0.TopTag(d) -> Ast.Code(top_level d)
  | Ast0.IsoWhenTag(_) -> failwith "not possible"
  | Ast0.IsoWhenTTag(_) -> failwith "not possible"
  | Ast0.IsoWhenFTag(_) -> failwith "not possible"
  | Ast0.MetaPosTag _ -> failwith "not possible"

(* --------------------------------------------------------------------- *)
(* Function declaration *)
(* top level isos are probably lost to tracking *)

and top_level t =
  rewrap t no_isos
    (match Ast0.unwrap t with
      Ast0.FILEINFO(old_file,new_file) ->
	Ast.FILEINFO(mcode old_file,mcode new_file)
    | Ast0.DECL(stmt) -> Ast.DECL(statement stmt)
    | Ast0.CODE(rule_elem_dots) ->
	Ast.CODE(statement_dots rule_elem_dots)
    | Ast0.ERRORWORDS(exps) -> Ast.ERRORWORDS(List.map expression exps)
    | Ast0.OTHER(_) -> failwith "eliminated by top_level")

(* --------------------------------------------------------------------- *)
(* Entry point for minus code *)

(* Inline_mcodes is very important - sends + code attached to the - code
down to the mcodes.  The functions above can only be used when there is no
attached + code, eg in + code itself. *)
let ast0toast_toplevel x =
  inline_mcodes.V0.combiner_top_level x;
  top_level x

let ast0toast name deps dropped exists x is_exp ruletype =
  List.iter inline_mcodes.V0.combiner_top_level x;
  Ast.CocciRule
    (name,(deps,dropped,exists),List.map top_level x,is_exp,ruletype)
