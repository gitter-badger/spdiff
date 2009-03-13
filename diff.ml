let debug = false
let debug_msg x = if debug then print_endline x else ()
let fdebug_string f x = if f then print_string x else ()
let fdebug_endline f x = if f then print_endline x else ()
let debug_newline () = if debug then print_newline () else ()


exception Fail of string

open Hashcons
open Gtree
open Db
open Difftype

type term = gtree
type up = term diff

type node = gtree
type edge = Control_flow_c2.edge

type gflow = (node, edge) Ograph_extended.ograph_mutable

exception Merge3

module GT =
struct
  type t = gtree
  let compare = Pervasives.compare
end

module DiffT =
struct
  (*type t = (((string,string) gtree) diff) list*)
  type t = gtree diff
  let compare = Pervasives.compare
end


(*
 *module DiffT =
 *  struct
 *    type t = ((string,string) gtree) diff
 *    let compare = Pervasives.compare
 *  end
 *
 *)
module DBM = Db(GT)
module DBD = Db(DiffT)

(* user definable references here ! *)
  (* copy from main.ml initialized in main-function *)
let verbose = ref false
(* use new and fancy malign algo to decide subpatch relation *)
let malign_mode = ref false
  (* terms are only abstracted until we reach this depth in the term *)
let abs_depth     = ref 0 
  (* only allow abstraction of subterms of terms that are smaller than this number
  *)
let abs_subterms  = ref 0
  (* the FV of rhs should be equal to lhs -- thus lhs can not drop metavars under
   * strict mode
   *)
let be_strict     = ref false 
  (* allow the same term to be abstracted by different metavariables
  *)
let use_mvars     = ref false
  (* should we really use the fixed information to prevent terms from getting
   * abstracted
   *)
let be_fixed      = ref false
  (* not used atm: should have indicated the number of allow exceptions as to how
   * often a patch should be found
   *)
let no_exceptions = ref 0
let no_occurs = ref 0
  (* should we be printing the derived abstract updates during inference
  *)
let print_abs = ref false
  (* should we allow non-matching parts to be safe? 
  *)
let relax = ref false
  (* copy of the main.ml var with the same name; initialized in main.ml *)
let do_dmine = ref false
  (* copy from main.ml; initialized in main.ml *)
let nesting_depth = ref 0
  (* have we not already initialized the table of abstracted terms *)
let not_counted = ref true
  (* hashtable for counting patterns *)
let count_ht = Hashtbl.create 591


let v_print s = if !verbose then (print_string s; flush stdout)
let v_print_string = v_print
let v_print_endline s = if !verbose then print_endline s
let v_print_newline () = v_print_endline ""


(* non-duplicating cons *)
let (+++) x xs = if List.mem x xs then xs else x :: xs

(* convenience for application *)
let (+>) o f = f o

let skip = mkA("SKIP","...")

(* check that list l1 is a sublist of l2 *)
let subset_list l1 l2 =
  List.for_all (function e1 -> (List.mem e1 l2)) l1

let string_of_meta p = match view p with
    (*| A ("meta", m) -> "$" ^ m*)
  | A ("meta", m) -> m
  | A (_, b) -> b
  | C _ -> raise (Fail "not meta")

let not_compound gt = match view gt with
  | C("comp{}", _) | A("comp{}", _) -> false
  | _ -> true

let is_assignment a_string = match a_string with 
  | "assign="
  | "assign+="
  | "assign-="
  | "assign*="
  | "assign%="
  | "assign/="
  | "assign&="
  | "assign|="
  | "assignx="
  | "assign?=?" -> true
  | _ -> false
      
let extract_aop a_string = match a_string with
  | "assign="  -> "="
  | "assign+=" -> "+="
  | "assign-=" -> "-="
  | "assign*=" -> "*="
  | "assign%=" -> "%="
  | "assign/=" -> "/="
  | "assign&=" -> "&="
  | "assign|=" -> "|="
  | "assignx=" -> "^="
  | "assign?=?" -> "?=?"
  | _ -> raise (Fail "Not assign operator?")

let rec string_of_gtree str_of_t str_of_c gt = 
  let rec string_of_itype itype = (match view itype with
    | A("itype", c) -> "char"
    | C("itype", [sgn;base]) ->
	(match view sgn, view base with
	  | A ("sgn", "signed") , A (_, b) -> "signed " ^ string_of_meta base
	  | A ("sgn", "unsigned"), A (_, b) -> "unsigned " ^ string_of_meta base
	  | A ("meta", _), A(_, b) -> b
	)) 
  and string_of_param param =
    match view param with
      | C("param", [reg;name;ft]) ->
          let r = match view reg with 
            | A("reg",r) -> r
            | A("meta",x0) -> string_of_meta reg in
          let n = match view name with
            | A("name", n) -> n
            | A("meta", x0) -> string_of_meta name in
            "(" ^ r ^ " " ^ n ^ ":" ^ string_of_ftype [ft] ^ ")"
      | _ -> loop param
  and string_of_ftype fts = 
    let loc cvct = match view cvct with
      | A("tqual","const") -> "const"
      | A("tqual","vola")  -> "volatile"
      | A("btype","void")  -> "void"
      | C("btype", [{node=C("itype", _)} as c])   -> string_of_itype c
      | C("btype", [{node=A("itype", _)} as a])   -> string_of_itype a
      | C("btype", [{node=A("ftype", ft)}]) -> ft
      | C("pointer", [ft]) -> "*" ^ string_of_ftype [ft]
      | C("array", [cexpopt; ft]) ->
          string_of_ftype [ft] ^ " " ^
            (match view cexpopt with
              | A("constExp", "none") -> "[]"
              | C("constExp", [e]) -> "[" ^ loop e ^ "]"
	      | A("meta", x0) -> string_of_meta cexpopt
            )
      | C("funtype", rt :: pars) -> 
          let ret_type_string = string_of_ftype [rt] in
          let par_type_strings = List.map string_of_param pars in
            "("^ 
              String.concat "**" par_type_strings 
            ^ ")->" ^ ret_type_string
      | C("enum", [{node=A ("enum_name", en)}; enumgt]) -> "enumTODO"
      | C("struct", [{node=C(sname, [stype])}]) -> 
          "struct " ^ sname ^ "{" ^ loop stype ^"}"
      | A ("struct", name) -> "struct " ^ name
      | _ -> loop cvct
      | C(tp,ts) -> tp ^ "<" ^ String.concat ", " (List.map loop ts) ^ ">"
      | A(tp,t) -> tp ^ ":" ^ t ^ ":"
    in
      String.concat " " (List.map loc fts)
  and loop gt =
    match view gt with
      | A ("meta", c) -> string_of_meta gt
	  (*      | A ("itype", _) -> string_of_itype gt 
      | A (t,c) -> t ^ ":" ^ c *)
      | C ("fulltype", ti) -> string_of_ftype ti
      | C ("const", [{node=A(_, c)}]) -> c
      | C ("itype", _ ) -> string_of_itype gt
      | C ("exp", [e]) -> loop e 
	  (*| C ("exp", [{node=A("meta", x0)}; e]) -> "(" ^ loop e ^ ":_)"*)
      | C ("exp", [{node=C ("TYPEDEXP", [t])} ; e]) ->
	  "(" ^ loop e ^ ":" ^ loop t ^ ")" 
	  (* loop e *)
      | C ("call", f :: args) ->
          loop f ^ "(" ^ String.concat "," (List.map loop args) ^ ")"
      | C ("binary_arith", [{node=A("aop",op_str)} ;e1;e2]) ->
          loop e1 ^ op_str ^ loop e2
      | C ("binary_logi", [{node=A("logiop", op_str)}; e1;e2]) ->
          loop e1 ^ op_str ^ loop e2
      | C ("record_ptr", [e;f]) -> 
          loop e ^ "->" ^ loop f
      | C ("record_acc", [e;f]) ->
          loop e ^ "." ^ loop f
      | C ("stmt", [st]) when not_compound st -> 
          loop st ^ ";"
      | C ("exprstmt", [gt]) -> loop gt
      | C (assignment, [l;r]) when is_assignment assignment ->
          loop l ^ extract_aop assignment ^ loop r
      | C ("&ref", [gt]) -> "&" ^ loop gt
      | C ("dlist", ds) -> ds +>
	  List.map loop +>
	  String.concat ", " 
      | C ("onedecl", [v;ft;sto]) ->
	  loop ft ^ " " ^ loop v ^ ";" (* storage and inline ignored *)
      | C ("stmt", [s]) -> loop s ^ ";"
      | C ("return", [e]) -> "return " ^ loop e
      | A ("goto", lab) -> "goto " ^ lab
      | C (t, gtrees) -> 
          str_of_t t ^ "[" ^
          String.concat "," (List.map loop gtrees)
          ^ "]"
      | A (t,c) -> c
(*      | A (t,c) -> str_of_t t ^ "<" ^ str_of_c c ^ ">" *)
  in
    loop gt

let verbose_string_of_gtree gt =
  let rec loop gt = match view gt with
    | A(t,c) -> t ^ "<" ^ c ^ ">"
    | C (t, gtrees) -> 
        t ^ "[" ^
          String.concat "," (List.map loop gtrees)
        ^ "]"
  in loop gt

let str_of_ctype x = x
let str_of_catom a = a

let string_of_gtree' = string_of_gtree str_of_ctype str_of_catom


let collect_metas gt = 
  let gs gt = match view gt with
    | A("meta",x) -> x ^ ";"in
  let (!!) gt = match view gt with
    | A("meta", _) -> true | _ -> false in
  let gtype gt = string_of_gtree' gt in
  let rec loop acc_metas gt = 
    if !!gt then (gs gt) +++ acc_metas
    else match view gt with
      | A _ -> acc_metas
      | C("const", [gt]) when !! gt -> ("const " ^ gs gt) +++ acc_metas
      | C("call", fargs) -> 
          fargs +> List.fold_left (fun acc_metas gt -> 
            match view gt with
              | _ when !! gt -> ("expression " ^ gs gt) +++ acc_metas
              | _ -> loop acc_metas gt
          ) acc_metas
      | C("exp",[gt']) when !!gt' -> ("expression " ^ gs gt') +++ acc_metas
      | C ("exp", [{node=C ("TYPEDEXP", [t])} ; e]) 
	  when !!e -> (gtype t ^ " " ^ gs e) +++ acc_metas
      | C ("record_acc", [e;f]) -> 
          let acc = if !! f 
          then ("identifier " ^ gs f) +++ acc_metas 
            else loop acc_metas f in
            if !! e 
            then ("expression " ^ gs e) +++ acc
            else loop acc e
      | C ("record_ptr", [e;f]) -> 
          let acc = if !! f 
          then ("identifier " ^ gs f) +++ acc_metas 
            else loop acc_metas f in
            if !! e 
            then ("expression " ^ gs e) +++ acc
            else loop acc e
      | C (_, gts) -> gts +> List.fold_left 
	  (fun acc_meta gt ->
	    loop acc_meta gt
	  ) acc_metas
  in
    loop [] gt
      
let rec string_of_diff d =
  let make_string_header gt = collect_metas gt in
    match d with
      | SEQ(p1,p2) -> "SEQ:  " ^ string_of_diff p1 ^ " ; " ^ string_of_diff p2
      | ID s -> "ID:  " ^ string_of_gtree str_of_ctype str_of_catom s
      | UP(s,s') -> 
	  "@@\n" ^ String.concat "\n" (make_string_header s) ^
	    "\n@@\n" ^
	    "- " ^ (string_of_gtree str_of_ctype str_of_catom s) ^ 
	    "\n" ^
	    "+ " ^ (string_of_gtree str_of_ctype str_of_catom s')
      | ADD s -> "ADD:  " ^ string_of_gtree str_of_ctype str_of_catom s
      | RM s -> "RM:  " ^ string_of_gtree str_of_ctype str_of_catom s

let extract_pat p = match view p with
| C("CM", [p]) -> p
| _ -> raise (Match_failure (string_of_gtree' p, 772,0))

let rec string_of_spdiff d =
  let make_string_header gt = collect_metas gt in
    match d with
      | SEQ(p1,p2) -> "SEQ:  " ^ string_of_spdiff p1 ^ " ; " ^ string_of_spdiff p2
      | ID s when s == skip -> "\t..."
      | ID s -> "\t" ^ extract_pat s +> string_of_gtree'
      | UP(s,s') -> 
	  "@@\n" ^ String.concat "\n" (make_string_header s) ^
	    "\n@@\n" ^
	    "- " ^ (string_of_gtree' s) ^ 
	    "\n" ^
	    "+ " ^ (string_of_gtree' s')
      | ADD s -> "+\t" ^ s +> string_of_gtree'
      | RM s -> "-\t" ^ extract_pat s +> string_of_gtree'

(* a solution is a list of updates, diff list and the idea is that it will
 * transform an original gt into the updated gt' *)
let print_sol sol =
  print_endline "[[";
  List.iter (function dg ->
    print_endline (string_of_diff dg);
    print_endline "\t++"
  ) sol;
  print_endline "]]"


let print_sols solutions =
  (*List.iter print_sol solutions*)
  print_sol solutions

let explode st =
  let rec loop i acc =
    if i = 0 
    then acc
    else 
      let i' = i-1 in 
	loop i' (st.[i'] :: acc) in
    List.map Char.escaped (loop (String.length st) [])
      
let spacesep st =
  Str.split (Str.regexp "[ ]+") st

let subset lhs rhs =
  List.for_all (function e -> List.mem e rhs) lhs

let lcs src tgt =
  let slen = List.length src in
  let tlen = List.length tgt in
  let m    = Array.make_matrix (slen + 1) (tlen + 1) 0 in
    Array.iteri (fun i jarr -> Array.iteri (fun j e -> 
      let i = if i = 0 then 1 else i in
      let j = if j = 0 then 1 else j in
      let s = List.nth src (i - 1) in
      let t = List.nth tgt (j - 1) in
	if s = t
	then
	  m.(i).(j) <- (try m.(i-1).(j-1) + 1 with _ -> 1)
	else 
	  let a = try m.(i).(j-1) with _ -> 0 in
	  let b = try m.(i-1).(j) with _ -> 0 in
	    m.(i).(j) <- max a b
    ) jarr) m;
    m

let rm_dub ls =
  (*List.rev *)
  (List.fold_left
      (fun acc e -> if List.mem e acc then acc else e :: acc)
      [] ls)

let max3 a b c = max a (max b c)

let lcs_shared size_f src tgt =
  let slen = List.length src in
  let tlen = List.length tgt in
  let m    = Array.make_matrix (slen + 1) (tlen + 1) 0 in
    Array.iteri 
      (fun i jarr -> Array.iteri 
	 (fun j e -> 
	    (* make sure we stay within the boundaries of the matrix *)
	    let i = if i = 0 then 1 else i in
	    let j = if j = 0 then 1 else j in
	      (* get the values we need to compare in s and t *)
	    let s = List.nth src (i - 1) in
	    let t = List.nth tgt (j - 1) in
	      (* now see how much of s and t is shared *)
	    let size = size_f s t in
	    let c = (try m.(i-1).(j-1) + size with _ -> size) in
	    let a = try m.(i).(j-1) with _ -> 0 in (* adding is better *)
	    let b = try m.(i-1).(j) with _ -> 0 in (* removing is better *)
	      m.(i).(j) <- max3 a b c
	 ) jarr) m; 
    m

let rec shared_gtree t1 t2 =
  let (+=) a b = if a = b then 1 else 0 in
  let rec comp l1 l2 =
    match l1, l2 with
      | [], _ | _, [] -> 0
          (* below: only do shallow comparison *)
          (*| x :: xs, y :: ys -> localeq x y + comp xs ys in*)
      | x :: xs, y :: ys -> shared_gtree x y + comp xs ys in
    match view t1, view t2 with
      | A (ct1, at1), A (ct2, at2) -> 
          (ct1 += ct2) + (at1 += at2)
      | C(ct1, ts1), C(ct2, ts2) ->
          (ct1 += ct2) + comp ts1 ts2
      | _, _ -> 0

let rec get_diff_nonshared src tgt =
  match src, tgt with
    | [], _ -> List.map (function e -> ADD e) tgt
    | _, [] -> List.map (function e -> RM e) src
    | _, _ -> 
	let m = lcs src tgt in
	let slen = List.length src in
	let tlen = List.length tgt in
	let rec loop i j =
	  (*     print_endline ("i,j = " ^ string_of_int i ^ "," ^ string_of_int j); *)
	  if i > 0 && j > 0 && List.nth src (i - 1) = List.nth tgt (j - 1)
	    (*if i > 0 && j > 0 && *)
	    (*embedded (List.nth src (i - 1)) (List.nth tgt (j - 1)) *)
	  then
	    loop (i - 1) (j - 1) @ [ID (List.nth src (i - 1))]
	  else if j > 0 && (i = 0 || m.(i).(j - 1) > m.(i - 1).(j))
	  then 
 	    loop i (j - 1) @ [ADD (List.nth tgt (j - 1))]
 	  else if 
            i > 0 && (j = 0 || m.(i).(j - 1) <= m.(i - 1).(j))
 	  then 
 	    loop (i - 1) j @ [RM (List.nth src (i - 1))]
	  else (assert(i=j && j=0) ;
		[]) (* here we should have that i = j = 0*)
	in loop slen  tlen

let rec get_diff_old src tgt =
  match src, tgt with
    | [], _ -> List.map (function e -> ADD e) tgt
    | _, [] -> List.map (function e -> RM e) src
    | _, _ -> 
	let m = lcs_shared shared_gtree src tgt in
	let slen = List.length src in
	let tlen = List.length tgt in
	let rec loop i j =
	  let i' = if i > 0 then i else 1 in
	  let j' = if j > 0 then j else 1 in
	  let s = List.nth src (i' - 1) in
	  let t = List.nth tgt (j' - 1) in
	    if i > 0 && j > 0 && (shared_gtree s t > 0)
	    then
	      let up = if s = t then ID s else UP(s,t) in
		loop (i - 1) (j - 1) @ [up]
	    else if j > 0 && (i = 0 || m.(i).(j - 1) >= m.(i - 1).(j))
	    then 
	      loop i (j - 1) @ [ADD (List.nth tgt (j - 1))]
	    else if 
		i > 0 && (j = 0 || m.(i).(j - 1) < m.(i - 1).(j))
	    then 
	      loop (i - 1) j @ [RM (List.nth src (i - 1))]
	    else (assert(i=j && j=0) ;
		  []) (* here we should have that i = j = 0*)
	in loop slen  tlen

let rec get_diff src tgt =
  match src, tgt with
    | [], _ -> List.map (function e -> ADD e) tgt
    | _, [] -> List.map (function e -> RM e) src
    | _, _ -> 
	let m = lcs_shared shared_gtree src tgt in
	let slen = List.length src in
	let tlen = List.length tgt in
	let rec loop i j =
	  if i > 0 && j = 0
	  then
	    loop (i - 1) j @ [RM (List.nth src (i - 1))]
	  else if j > 0 && i = 0
	  then
	    loop i (j - 1) @ [ADD (List.nth tgt (j - 1))]
	  else if i > 0 && j > 0
	  then
	    let s = List.nth src (i - 1) in
	    let t = List.nth tgt (j - 1) in
	    let score      = m.(i).(j) in
	    let score_diag = m.(i-1).(j-1) in
	    let score_up   = m.(i).(j-1) in
	    let score_left = m.(i-1).(j) in
	      if score = score_diag + (shared_gtree s t)
	      then
		let up = if s = t then ID s else UP(s,t) in
		  loop (i - 1) (j - 1) @ [up]
	      else if score = score_left
	      then
		loop (i - 1) j @ [RM (List.nth src (i - 1))]
	      else if score = score_up
	      then
		loop i (j - 1) @ [ADD (List.nth tgt (j - 1))]
	      else raise (Fail "?????")
	  else
	    (assert(i=j && j = 0); [])
	in loop slen  tlen
	     

(* normalize diff rearranges a diff so that there are no consequtive
 * removals/additions if possible.
 *)
let normalize_diff diff =
  let rec get_next_add prefix diff = 
    match diff with
      | [] -> None, prefix
      | ADD t :: diff -> Some (ADD t), prefix @ diff
      | t :: diff -> get_next_add (prefix @ [t]) diff
  in 
  let rec loop diff =
    match diff with
      | [] -> []
      | RM t :: diff' -> 
          let add, tail = get_next_add [] diff' in
            (match add with
               | None -> RM t :: loop tail
               | Some add -> RM t :: add :: loop tail)
      | UP(t,t') :: diff -> RM t :: ADD t' :: loop diff
      | i :: diff' -> i :: loop diff' in 
    loop diff

(* correlate_diff tries to take sequences of -+ and put them in either
   UP(-,+) or ID. Notice, that permutations of arguments is not
   detected and not really supported in the current framework either
*)

(* sub_list p d takes a list d and returns the prefix-list of d of elements all
 * satisfying p and the rest of the list d
 *)
let sub_list p d =
  let rec loop d =
    match d with
      | [] -> [], []
      | x :: xs -> 
          if p x 
          then 
            let nxs, oxs = loop xs in
              x :: nxs, oxs
          else [], x :: xs
  in
    loop d

let rec correlate rm_list add_list =
  match rm_list, add_list with
    | [], [] -> []
    | [], al -> al
    | rl, [] -> rl
    | RM r :: rl, ADD a :: al ->
        let u = if r = a then ID a else UP(r,a) 
        in
          u :: correlate rl al
    | _ -> raise (Fail "correleate")
	
(* the list of diffs returned is not in the same order as the input list
*)
let correlate_diffs d =
  let rec loop d =
    match d with
      | [] -> [], []
      | RM a :: d -> 
          let rm_list, d = sub_list 
            (function x -> match x with 
              | RM _ -> true 
	      | _ -> false) ((RM a) :: d) in
          let add_list, d = sub_list
            (function x -> match x with 
              | ADD _ -> true 
              | _ -> false) d in
          let ups' = correlate rm_list add_list in
          let ups, d' = loop d in
            ups' @ ups , d'
      | x :: d -> match loop d with up, d' -> up, x :: d' in
  let rec fix_loop (ups, d_old) d =
    let ups_new, d_new = loop d in
      if d_new = d_old
      then ups_new @ ups, d_new
      else fix_loop (ups_new @ ups, d_new) d_new
  in
  let n, o = fix_loop ([], []) d in
    n @ o


exception Nomatch

(* Take an env and new binding for m = t; if m is already bound to t then we
 * return the same env, and else we insert it in front The key point is that we
 * get an exception when we try to bind a variable to a NEW value!
 *)
let merge_update env (m, t) =
  try
    let v = List.assoc m env in
      if v = t
      then env
      else raise Nomatch
  with _ -> (m,t) :: env

(* take two environments; for each binding of m that is in both env1 and env2,
 * the binding must be equal; for variables that are in only one env, we simply
 * add it
 *)
let merge_envs env1 env2 =
  List.fold_left (fun env (m,t) -> merge_update env (m,t)) env2 env1

let mk_env (m, t) = [(m, t)]
let empty_env = ([] : ((string * gtree) list))

let rev_lookup env t =
  let rec loop env = match env with 
  | [] -> None
  | (m,t') :: env when t = t' -> Some m
  | _ :: env -> loop env
  in
  loop env 


(* replace subterms of t that are bound in env with the binding metavariable
   so subterm becomes m if m->subterm is in env
   assumes that m1->st & m2->st then m1 = m2
   i.e. each metavariable denote DIFFERENT subterms
*)
let rec rev_sub env t =
  match rev_lookup env t with
  | Some m -> mkA("meta", m)
  | None -> (match view t with 
    | C(ty, ts) -> mkC(ty, ts +> List.fold_left
		      (fun acc_ts t -> rev_sub env t :: acc_ts) []
		      +> List.rev)
    | _ -> t)


let rec sub env t =
  if env = [] then t else
    let rec loop t' = match view t' with
      | C (ct, ts) ->
          mkC(ct, List.rev (
            List.fold_left (fun b a -> (loop a) :: b) [] ts
          ))
      | A ("meta", mvar) -> (try 
	    List.assoc mvar env with (Fail _) ->
              (print_endline "sub?"; mkA ("meta", mvar)))
      | _ -> t'
    in
      loop t

(* try to see if a term st matches another term t
*)
let rec match_term st t =
  match view st, view t with
    | A("meta",mvar), _ -> mk_env (mvar, t)
    | A(sct,sat), A(ct,at) when sct = ct && sat = at -> empty_env
	(* notice that the below lists s :: sts and t :: ts will always match due to
	 * the way things are translated into gtrees. a C(type,args) must always have
	 * at least ONE argument in args 
	 *)
    | C(sct,s :: sts), C(ct, t :: ts) when 
	  sct = ct && List.length sts = List.length ts -> 
        List.rev (
          List.fold_left2 (fun acc_env st t ->
            merge_envs (match_term st t) acc_env
          ) (match_term s t) sts ts)
    | _ -> raise Nomatch

let is_read_only t = match view t with 
  | C("RO", [t']) -> true
  | _ -> false
let get_read_only_val t = match view t with
  | C("RO", [t']) -> t'
  | _ -> raise Nomatch

let mark_as_read_only t = mkC("RO", [t])

let can_match p t = try match match_term p t with _ -> true with Nomatch -> false

(* 
 * occursht is a hashtable indexed by a pair of a pattern and term 
 * the idea is that each (p,t) maps to a boolean which gives the result of
 * previous computations of "occurs p t"; if no previous result exists, one is
 * computed
 *)

module PatternTerm = struct
  type t = gtree * gtree
  let equal (p1,t1) (p2,t2) =
    p1 == p2 && t1 == t2
  let hash (p,t) = abs (19 * (19 * p.hkey + t.hkey) + 2)
end

module Term = struct
  type t = gtree
  let equal t t' = t == t'
  let hash t = t.hkey
end

module TT = Hashtbl.Make(Term)

module PT = Hashtbl.Make(PatternTerm)



let occursht = PT.create 591

let find_match pat t =
  let cm = can_match pat in
  let rec loop t =
    cm t || match view t with
      | A _ -> false
      | C(ct, ts) -> List.exists (fun t' -> loop t') ts
  in 
    try 
      if
	PT.find occursht (pat,t) 
      then true
      else (
	(*	print_endline ("pattern1: " ^ string_of_gtree' pat);
		print_endline ("pattern2: " ^ string_of_gtree' t); *)
	false)

    with Not_found -> 
      let res = loop t in
	(PT.add occursht (pat,t) res; 
	 res)

let is_header head_str = 
  head_str.[0] = 'h' &&
  head_str.[1] = 'e' &&
  head_str.[2] = 'a' &&
  head_str.[3] = 'd'

let non_phony p = match view p with
  | A("phony", _) 
  | C("phony", _)
  | A(_, "N/H") 
  | A(_, "N/A") -> false
(*
  | A(head,_)
  | C(head,_) -> not(is_header head)
*)
  | _ -> true

let find_nested_matches pat t =
  let mt t = try Some (match_term pat t) with Nomatch -> None in
  let rec loop depth acc_envs t = 
    if depth = 0
    then acc_envs
    else 
      let acc_envs' = (match mt t with
        | Some e -> e :: acc_envs
        | None -> acc_envs) in
        match view t with 
          | A _ -> acc_envs'
          | C(_, ts) -> let l = loop (depth - 1) in
                          List.fold_left l acc_envs' ts
  in
    (* loop !nesting_depth [] t *)
    if non_phony t
    then loop !nesting_depth [] t
    else []

let can_match_nested pat t =
  match find_nested_matches pat t with
    | [] -> false 
    | _ -> true

let return_and_bind (up,t) (t',env) = (
  t',env
)

let get_unique ls =
  let rec loop acc ls = match ls with
    | [] -> acc
    | e :: ls when List.mem e ls -> loop (e :: acc) ls
    | _ :: ls -> loop acc ls in
  let dupl = loop [] ls in
    List.filter (function e -> not(List.mem e dupl)) ls

let get_common_unique ls1 ls2 =
  let uniq1 = get_unique ls1 in
    get_unique ls2 
    +> List.filter (function u2 -> List.mem u2 uniq1)

let patience_ref nums =
  let get_rev_index ls = List.length ls in
  let lookup_rev i ls = List.length ls - i +> List.nth ls  in
  let insert left e ls = match left with
    | None -> (None, e) :: ls
    | Some (stack) -> (Some (get_rev_index stack), e) :: ls in
  let (<) n n' = n < (snd n') in
  let (>>) stacks n = 
    let rec loop left stacks n =
      match stacks with 
	| [] -> [insert left n []]
	| (n' :: stack) :: stacks when n < n' -> (insert left n (n' :: stack)) :: stacks
	| stack :: stacks  -> stack :: (loop (Some stack) stacks n)
    in loop None stacks n
  in
  let stacks = List.fold_left (>>) [] nums in
    (* get the lcs *)
  let rec lcs acc_lcs id remaining_stacks =
    match remaining_stacks with
      | [] -> acc_lcs
      | stack :: stacks ->
          let (nid_opt, e) = lookup_rev id stack in
            (match nid_opt with 
              | None -> e :: acc_lcs
              | Some nid -> lcs (e :: acc_lcs) nid stacks)
  in
    match List.rev stacks with
      | [] -> []
      | [(_, e) :: stack] -> [e]
      | ((Some nid, e) :: _) :: stacks -> lcs [e] nid stacks

let get_slices lcs_orig ls_orig =
  let take_until e ls =
    let rec loop acc ls = match ls with
      | [] -> (
          let lcs_str = List.map string_of_gtree' lcs_orig +> String.concat " " in
          let ls_str = List.map string_of_gtree' ls_orig +> String.concat " " in
            print_endline "Exception";
            print_endline ("lcs: " ^ lcs_str);
            print_endline ("ls_str: " ^ ls_str);
            raise (Fail "get_slices:take_until "))
      | e' :: ls when e = e' -> List.rev acc, ls
      | e' :: ls -> loop (e' :: acc) ls
    in loop [] ls
  in
  let rec loop lcs ls =
    match lcs with
      | [] -> [ls]
      | e :: lcs -> let slice, ls = take_until e ls in 
                      slice :: loop lcs ls
  in loop lcs_orig ls_orig

let rec patience_diff ls1 ls2 =
  (* find the index of the given unique term t in ls *)
  let get_uniq_index ls t = 
    let rec loop ls n = match ls with
      | [] -> raise (Fail "not found get_uniq_index")
      | t' :: ls when t = t' -> n
      | _ :: ls -> loop ls (n + 1)
    in
      loop ls 0 in
    (* translate a list of terms from ls2 such that each term is replaced with its index in ls1 *)
  let rec to_nums c_uniq_terms = match c_uniq_terms with
    | [] -> []
    | t :: terms -> get_uniq_index ls1 t :: to_nums terms in
  let common_uniq = get_common_unique ls1 ls2 in
  let nums = to_nums common_uniq in
    (* translate a list of nums to their corresponding terms in ls1 *)
  let to_terms ns = List.map (List.nth ls1) ns in
  let lcs = nums +> patience_ref +> to_terms in
    if lcs = []
    then (* ordinary diff *) 
      get_diff ls1 ls2
    else 
      let slices1 = get_slices lcs ls1 in
      let slices2 = get_slices lcs ls2 in
      let diff_slices = List.map2 patience_diff slices1 slices2 in
      let rec merge_slice lcs dslices = match dslices with
	| [] -> []
	| diff :: dslices -> diff @ merge_lcs lcs dslices
      and merge_lcs lcs dslices = match lcs with
	| [] -> (match dslices with
		   | [] -> []
		   | [diff] -> diff
		   | _ -> raise (Fail "merge_lcs : dslice not singular"))
	| e :: lcs -> ID e :: merge_slice lcs dslices
      in merge_slice lcs diff_slices

let a_of_type t = mkA("nodetype", t)
let begin_c t = mkA("begin",t)
let end_c t = mkA("end",t)
    
let flatht = TT.create 1000001

let rec flatten_tree gt = 
  let loop gt =
    match view gt with 
      | A _ -> [gt]
	  (*| C(t, gts) -> List.fold_left (fun acc gt -> List.rev_append (flatten_tree gt) acc) [] gts*)
(*
      | C(t, gts) -> a_of_type t :: List.fold_left 
				     (fun acc gt -> List.rev_append (flatten_tree gt) acc) 
				     [] (List.rev gts)
*)
      | C(t, gts) -> 
	  begin_c t ::
	    List.fold_left
	    (fun acc gt -> List.rev_append (flatten_tree gt) acc) 
	    [end_c t] (List.rev gts)
  in 
    try 
      TT.find flatht gt
    with Not_found ->
      let 
	  res = loop gt in
	(
	  TT.add flatht gt res;
	  res
	)

let rec linearize_tree gt =
  let rec loop acc gt = 
    match view gt with
      | A _ -> gt +++ acc
      | C(_, gts) -> gts +> List.fold_left loop (gt +++ acc)
  in
    loop [] gt

let tail_flatten lss =
  lss +> List.fold_left List.rev_append []

let get_tree_changes_old gt1 gt2 = 
  let is_up op = match op with UP _ -> true | _ -> false in
  let get_ups (UP(gt1, gt2)) =
    if gt1=gt2 then [] else
      match view gt1, view gt2 with
	| C(_, gts1), C(_, gts2) ->
            UP(gt1, gt2) :: (patience_diff gts1 gts2 +>
			       correlate_diffs +>
			       List.filter is_up)
	| _, _ -> [UP(gt1,gt2)] in
  let rec fix (=) f prev =
    let next = f prev in
      if next = prev then prev else fix (=) f next
  in
  let unwrap up = match up with UP(a,b) -> (a,b) in
  let f ups = 
    ups +>
      List.rev_map get_ups +>
      tail_flatten +>
      List.rev_append ups +>
      rm_dub
  in
  let eq l1 l2 = 
    l1 +> List.for_all (function e1 -> List.mem e1 l2) &&
      l2 +> List.for_all (function e2 -> List.mem e2 l1) in
    fix eq f [UP(gt1,gt2)]

let get_tree_changes gt1 gt2 =
  let is_up op = match op with UP _ -> true | _ -> false in
  let get_ups (UP(gt1,gt2) as up) = 
    if gt1 = gt2 then []
    else match view gt1, view gt2 with
      | C(t1, gts1), C(t2, gts2) when t1 = t2 ->
          (patience_diff gts1 gts2
	     (* (function dfs ->  *)
	     (* 	dfs +> List.iter (function iop ->  *)
	     (* 			    print_endline ( *)
	     (* 			    match iop with *)
	     (* 			    | ID p -> "\t" ^ string_of_gtree' p *)
	     (* 			    | RM p -> "-\t" ^ string_of_gtree' p *)
	     (* 			    | ADD p -> "+\t" ^ string_of_gtree' p *)
	     (* 			    | UP(p,p') -> "~>\t" ^ string_of_gtree' p ^  *)
	     (* 				"\n\t" ^ string_of_gtree' p') *)
	     (* 			 ); *)
	     (* 	print_endline "---"; *)
	     (* 	dfs *)
	     (* ) *)
	   +> correlate_diffs 
	   +> List.filter is_up)
      | _, _ -> [] in
  let (@@) ls1 ls2 = ls1 +> 
    List.fold_left (fun acc_ls e -> e +++ acc_ls) ls2 in
  let rec loop work acc =
    match work with 
      | [] -> acc
      | up :: work ->
	  let new_work = get_ups up in
	    loop (new_work @@ work) (up :: acc)
  in
    loop [UP(gt1,gt2)] []
	    

let editht = PT.create 1000001


type 'a label = V of 'a | L

let get_tree_label t = match view t with
  | A (c,l) -> c^l
  | C(l,_) -> l

let label_dist l1 l2 = match l1, l2 with
  | L, L -> 0
  | L, _ | _, L -> 1
  | V t1, V t2 -> 
      if get_tree_label t1 = get_tree_label t2
      then 0
    else 1


let min3 a b c = min a (min b c) 

  (*
  if b < c 
  then if a < b
  then (print_endline "a"; a)
  else (print_endline "b"; b)
  else if a < c 
  then (print_endline "a"; a)
  else (print_endline "c"; c)
*)

exception Rm_leftmost

let rm_leftmost f1 =
        match f1 with
        | [] -> raise Rm_leftmost
        | t :: f -> (match view t with
          | A _ -> t, f
          | C(_, ts) -> t, ts @ f)

exception Rm_leftmost_tree

let rm_leftmost_tree f1 = match f1 with
  | [] -> raise Rm_leftmost_tree
  | _ :: f -> f

let get_head_forest f = match f with
  | [] -> raise (Fail "empty forest in get_head_forest")
  | t :: _ -> (match view t with
    | A _ -> []
    | C(_,ts) -> ts)

let get_leftmost f = match f with
  | [] -> raise (Fail "no leftmost")
  | t :: _ -> t

let rec forest_dist f1 f2 =
  match f1, f2 with
    | [], [] -> 0
    |  _, [] -> let v, f1' = rm_leftmost f1 in
         forest_dist f1' f2 + 
           label_dist (V v) L
    | [],  _ -> let w, f2' = rm_leftmost f2 in
        forest_dist f1 f2' +
          label_dist L (V w)
    |  _,  _ -> 
	 let v, f1mv = rm_leftmost f1 in
	 let w, f2mw = rm_leftmost f2 in
	   min3 
             (
	       forest_dist f1mv f2 + label_dist (V v) L
             )
             (
	       forest_dist f1 f2mw + label_dist L (V w)
             )
             (let f1v  = get_head_forest f1 in
              let f2w  = get_head_forest f2 in
              let f1mv = rm_leftmost_tree f1 in
              let f2mw = rm_leftmost_tree f2 in
		forest_dist f1v f2w +
		  forest_dist f1mv f2mw +
		  label_dist (V v) (V w)
             )


let minimal_tree_dist t1 t2 = forest_dist [t1] [t2]

let rec msa_cost gt1 gt2 gt3 =
  gt1 = gt2 || gt2 = gt3 ||
  match view gt1, view gt2, view gt3 with
    | C(ty1,ts1), C(ty2,ts2), C(ty3,ts3) when 
	ty1 = ty2 || ty2 = ty3 ->
	Msa.falign msa_cost 
	  (Array.of_list ts1)
	  (Array.of_list ts2)
	  (Array.of_list ts3)
    | _ -> false
(*
  let seq1 = Array.of_list (flatten_tree gt1) in
  let seq2 = Array.of_list (flatten_tree gt2) in
  let seq3 = Array.of_list (flatten_tree gt3) in
  let callb t1 t2 t3 = t1 = t2 || t2 = t3 in
    Msa.falign callb seq1 seq2 seq3
*)

let rec edit_cost gt1 gt2 =
  let rec node_size gt = match view gt with
    | A _ -> 1
    | C (_, ts) -> ts +> List.fold_left (fun sum t -> sum + node_size t) 1 in
  let up_cost up = match up with
    | ID _ -> 0
    | RM t | ADD t -> node_size t
    | UP (t1,t2) when t1  = t2 -> 0
    | UP (t,t') -> node_size t + node_size t'
  in
  let get_cost gt1 g2 =
    patience_diff (flatten_tree gt1) (flatten_tree gt2) +>
      List.fold_left (fun acc_sum up -> up_cost up + acc_sum) 0 in
  let rec get_cost_tree gt1 gt2 = 
    if gt1 = gt2 then 0
    else 
      match view gt1, view gt2 with
	| C(t1,gts1), C(t2,gts2) -> 
	    (if t1 = t2 then 0 else 1) + (
	      patience_diff gts1 gts2 +>
		(*get_diff gts1 gts2 +> *)
		List.fold_left (fun acc_sum up -> match up with
				  (* | UP(t1,t2) -> get_cost_tree t1 t2 + acc_sum *)
				  | UP(t1,t2) -> edit_cost t1 t2 + acc_sum
				  | _ -> up_cost up + acc_sum) 0)
	(* | _ -> 1  *)
	| _ -> up_cost (UP(gt1,gt2)) 
  in
    try
      let res = PT.find editht (gt1,gt2) in
	res
    with Not_found ->
      let 
	(* res = minimal_tree_dist gt1 gt2 *)
	  res = get_cost_tree gt1 gt2
	  (* res = get_cost gt1 gt2 *)
      in
	(
	  PT.add editht (gt1,gt2) res;
	  res
	)
	

(* apply up t, applies up to t and returns the new term and the environment bindings *)
let rec apply up t =
  match up with (*
                  | RM p -> (match t with 
                  | C(ct, ts) -> 
                  let ts' = List.rev (List.fold_left (fun acc_ts t ->
                  if can_match p t
                  then acc_ts
                  else 
                  let t1 = fst(try apply up t with Nomatch -> (t, empty_env)) 
                  in t1 :: acc_ts
                  ) [] ts) in
                  C(ct,ts), empty_env
                  | _ -> raise Nomatch
                  ) *)
    | SEQ(d1, d2) -> 
        (* For a sequence, we must actually apply all embedded rules in parallel
         * so that the result of applying rule1 is never used for rule2 otherwise
         * the presence of p->p' and p'->p would cause the inference to never
         * terminate! At the moment we silently ignore such cases!
         *)
        (* ---> this is old code <--- *)
        let t1, env1 = (try 
            apply d1 t with Nomatch -> 
              if !relax then t, empty_env else raise Nomatch)
        in
          (try apply d2 t1 with Nomatch ->
            if !relax 
            then t1, empty_env
            else raise Nomatch
          )
    | UP(src, tgt) -> 
        (*
         * This is where we now wish to introduce the occurs check using
         * a hashtable to memoize previous calls to "find_match"
         *)
        if not(find_match src t)
        then raise Nomatch
        else
          (match view src, view t with
            | A ("meta", mvar), _ -> 
                let env = mk_env (mvar, t) in 
                  return_and_bind  (up, t) (sub env tgt,env)
            | A (sct, sat), A(ct, at) when sct = ct && sat = at ->
                return_and_bind  (up, t) (tgt, empty_env)
            | C (sct, sts), C(ct, ts) when sct = ct -> 
                (try
                    (*print_endline *)
                    (*("trying " ^ string_of_gtree str_of_ctype str_of_catom t);*)
                    let fenv = List.fold_left2 (fun acc_env st t ->
                      let envn = match_term st t in
                        merge_envs envn acc_env
                    ) empty_env sts ts in
                    let res = sub fenv tgt in
                      (*print_endline ("result: " ^*)
                      (*string_of_gtree str_of_ctype str_of_catom res); *)
                      return_and_bind  (up,t) (res, fenv)
                  with _ -> 
                    (*print_endline "_";*)
                    let ft, flag = List.fold_left
                      (fun (acc_ts, acc_flag) tn -> 
                        let nt, flag = (match apply_some up tn with
                          | None -> tn, false
                          | Some t -> t, true) in
                          nt :: acc_ts, flag || acc_flag
                      ) ([], false) ts in
                      if flag 
                      then return_and_bind  (up,t) (mkC(ct, List.rev ft), empty_env)
                      else (* no matches at all *) raise Nomatch
			(*let ft = List.fold_right (fun tn acc_ts ->*)
			(*let nt, _ = apply up tn in*)
			(*nt :: acc_ts) (t :: ts) [] in*)
			(*C(ct, ft), empty_env*)
                )
            | _, C (ct, ts) -> 
                (*print_endline ("dive " ^ ct);*)
                let ft, flag = List.fold_left
                  (fun (acc_ts, acc_flag) tn -> 
                    let nt, flag = (match apply_some up tn with
                      | None -> tn, false
                      | Some t -> t, true) in
                      nt :: acc_ts, flag || acc_flag
                  ) ([], false) ts in
                  if flag 
                  then return_and_bind  (up,t) (mkC(ct, List.rev ft), empty_env)
                  else (* no matches at all *) raise Nomatch
            | _ -> (
                (*print_endline "nomatch of ";*)
                (*print_endline (string_of_diff up);*)
                (*print_endline "with";*)
                (*print_endline (string_of_gtree str_of_ctype str_of_catom t);*)
                raise Nomatch)
          )
    | _ -> raise (Fail "Not implemented application")

and apply_noenv up t =
  let newterm, _ = apply up t in newterm


and eq_term t bp1 bp2 =
  (try
      let t1 = apply_noenv bp1 t in 
	(try
            t1 = apply_noenv bp2 t
          with Nomatch -> false)
    with Nomatch -> 
      try let _ = apply_noenv bp2 t in 
	    false 
      with Nomatch -> true)

and eq_changeset chgset bp1 bp2 =
  List.for_all (function (t,_) -> eq_term t bp1 bp2) chgset

and apply_some up t = 
  try ( 
    let nt, _ = (apply up t) 
    in Some nt) with Nomatch -> None

and safe_apply up t =
  try apply_noenv up t with Nomatch -> t

(* this function tries to match the assumed smaller term small with the assumed
 * larger term large; meta-variables are allowed in both terms, but only the
 * ones in small forces a binding; we assume that either the smaller term can
 * only match in one way to the larger; we use an eager matching strategy
 *)
and occurs_meta small large =
  let rec loc_loop env s ts =
    (match ts with
      | [] -> raise Nomatch
      | t :: ts -> try loop env s t with Nomatch -> loc_loop env s ts)
  and loop env s l = match view s, view l with
    | _, _ when s == l -> [] 
    | A ("meta", mvar), _ -> merge_update env (mvar, l)
    | C (lt, lts), C(rt, rts) ->
	(* first try to match eagerly *)
        (try
            (if lt = rt && List.length lts = List.length rts
            then 
              (* each term from lts must match one from rts *)
              List.fold_left2 (fun acc_env s l -> loop acc_env s l) env lts rts
              else raise Nomatch)
          with Nomatch ->
	    (* since that failed try to find a matching of the smaller terms of the
	     * large term*)
            loc_loop env s rts)
    | _, _ -> raise Nomatch
  in
    (try (loop [] small large; true) with Nomatch -> false)

(* this function takes a term t1 and finds all the subterms of t2 where t1 can
 * match; the returned result is a list of all the subterms of t2 that were
 * matched
 *)
(*
  and matched_terms t t' =
  match t, t' with
  | A _, A _ -> (try let env = match_term t t' in [t', env] with Nomatch -> [])
  | _, C(ct, ts) ->
  let res  = try [t', match_term t t'] with Nomatch -> [] in
  let mres = List.map (matched_terms t) ts in
  let g' acc (ti, envi) = 
  try 
  let envj = List.assoc ti acc in
  if subset envj envi && subset envi envj
  then acc
  else (ti, envi) :: acc
  with Not_found -> (ti, envi) :: acc in
  let g acc rlist = List.fold_left g' acc rlist in
  List.fold_left g res mres
  | _, _ -> []

  and safe_update_old gt1 gt2 up =
  match up with 
  | UP(l,r) -> (
  try 
  let tgt = apply_noenv up gt1 in
  if tgt = gt2
  then (
(*print_endline ("patch applied cleanly:" ^ *)
(*string_of_diff up);*)
  true)
  else (
(*print_endline ("nonequal apply  :::: " ^*)
(*string_of_diff up);*)
  try (
  let mt1 = matched_terms r gt2 in
(*print_string "mt1 {";*)
(*List.iter (fun (t, _) -> print_endline (string_of_gtree' t)) mt1;*)
(*print_endline "}";*)
  let mt2 = matched_terms r tgt in
(*print_string "mt2 {";*)
(*List.iter (fun (t, _) -> print_endline (string_of_gtree' t)) mt2;*)
(*print_endline "}";*)
  subset mt1 mt2 && subset mt2 mt1
  ) with Nomatch -> (print_endline "nope";false)
  )
(* since the update did'nt apply, it is *safe* to include it as it will
  * not transform the gt1,gt2 pair *)
  with Nomatch -> true 
  )
  | _ -> raise (Fail "unsup safe_up")
*)
and invert_up up = 
  match up with
    | UP(l,r) -> UP(r, l)
    | _ -> raise (Fail "unsup invert_up")


(* check that up is a part of the update from term gt1 to gt2;
 * either up ~= (gt1, gt2)
 * orelse (gt1,gt2);up-1 ~= up
 *)
and safe_update gt1 gt2 up =
  try
    let tgt_l = apply_noenv up gt1 in
      if tgt_l = gt2 
      then true
      else
	try
          let tgt_r = apply_noenv (invert_up up) gt2 in
          let gt2'  = apply_noenv up tgt_r in
            gt2' = gt2
	with Nomatch -> false
  with Nomatch -> false

(* sometime it is useful to be able to check that a patch can be applied safely
 * before another patch
 *)
and safe_before (gt1, gt2) up1 up2 = 
  try
    not(subpatch_single up1 up2 (gt1, gt2)) && 
      safe_part (SEQ(up1,up2)) (gt1, gt2)
  with Nomatch -> false

and safe_before_pairs term_pairs up1 up2 =
  let safe_pred = fun p -> safe_before p up1 up2 in
    List.for_all safe_pred term_pairs

and sort_safe_before_pairs term_pairs upds =
  let (-->) up1 up2 = safe_before_pairs term_pairs up1 up2 in
  let rec insert_before d ds = match ds with 
    | [] -> [d]
    | d' :: ds when d --> d' -> d :: d' :: ds
    | d' :: ds -> d' :: insert_before d ds in
  let rec sort ds = match ds with 
    | [] -> []
    | d :: ds -> insert_before d (sort ds) in
    sort upds


and traverse pred work lhs rhs =
  let rec add_ups pred ups work = 
    List.fold_left pred work ups in
  let rec loop work t t' = match view t, view t' with
    | C(tp,ts), C(tp',ts') when tp = tp' && List.length ts = List.length ts' ->
	(*List.fold_left2 loop (add_ups pred [UP(t,t')] work) ts ts'*)
	List.fold_left2 loop (pred work (UP(t,t'))) ts ts'
	  (* TODO: we should consider how to handle removals as they could also
	     be considered "context-free", but for the time being we have no good
	     way to handle those *)
	  (*
	    | C(tp,ts), C(tp',ts') when tp = tp' && List.length ts < List.length ts' ->
	  (* we have a removal-case; there could be more than one
	    removed term though so we need to be careful to find the ones
	    that were actually removed *)
	  *)
    | _, _ -> pred work (UP(t,t')) (*add_ups pred [UP(t,t')] work *) in
    loop work lhs rhs

and complete_part lhs rhs w u =
  try
    if apply_noenv u lhs = rhs 
    then u :: w else w
  with Nomatch -> w

and complete_parts gt1 gt2 =
  traverse (complete_part gt1 gt2) [] gt1 gt2
and isid_up (UP(a,b)) = a = b
  (* returns every[1] term update that could have occurred when updating the term
   * given by gt1 into the term given by gt2; one should notice that such an
   * update may not be safe to apply directly as it might transform parts of gt1
   * that were not supposed to be transformed; maybe a better notion for what this
   * function returns is a mapping from terms that changed into what they were
   * changed into
   *
   * [1] when we reach a pair of terms c(ts), c'(ts') and c!=c' and |ts|!=|ts'| we
   * stop the recursion and simply return the pair; one could consider whether it
   * would be appropriate to also dive into at least the parts of ts and ts' that
   * were the same
   *)
and all_maps gt1 gt2 =
  let all_pred lhs rhs w u =
    if 
      not(List.mem u w) && 
	not(isid_up u)
    then u :: w
    else w
  in
    traverse (all_pred gt1 gt2) [] gt1 gt2

and part_of lhs rhs w u =
  let gta     = apply_noenv u lhs in
  let gtb     = apply_noenv (invert_up u) rhs in
    if gta = rhs || gtb = lhs 
    then u :: w 
    else
      let parts_a = complete_parts gta rhs in
      let parts_b = complete_parts lhs gtb in
	if List.exists (fun bp -> List.mem bp parts_b) parts_a
	then u :: w
	else w


and get_ctf_diffs_new f work gt1 gt2 =
  traverse (part_of gt1 gt2) work gt1 gt2


(*and safe_list (UP(l,r)) c_parts =*)
and safe_list u c_parts =
  (* check that there no parts transforming read_only parts *)
  (debug_msg "****";
   List.iter (function p -> debug_msg (string_of_diff p)) c_parts;
   debug_msg "####";
   List.for_all (function u -> match u with
     | UP(a,b) when is_read_only a -> 
         if get_read_only_val a = b
         then true
         else (
           debug_msg ("violation: " ^ string_of_diff (UP(a,b))); 
           false)
     | UP(a,b) -> true
   ) 
     c_parts)
    
and mark_update up = match up with 
  | UP(l, r) -> UP(l, mark_as_read_only r)
  | SEQ(d1,d2) -> SEQ(mark_update d1, mark_update d2)

and safe_part_old t t' up =
  try
    let up_marked = mark_update up in
    let t'' = apply_noenv up_marked t in
      (debug_msg ("checking safety : " ^ string_of_diff up);
       debug_newline ();
       let c_parts = all_maps t'' t' in
	 if safe_list up c_parts
	 then (debug_msg "... safe"; true)
	 else (debug_msg "...unsafe"; false)
      )
  with Nomatch -> false


and fold_left3 f acc ts1 ts2 ts3 =
  let rec loop acc ts1 ts2 ts3 = match ts1, ts2, ts3 with
    | [], [], [] -> acc 
    | t1 :: ts1, t2 :: ts2, t3 :: ts3 -> loop (f acc t1 t2 t3) ts1 ts2 ts3 
    | _, _, _ -> raise Merge3 in
    loop acc ts1 ts2 ts3

(* t'' is safely reachable from t' which originated in t *)
and merge3 t1 t2 t3 =
  let m3 acc t1 t2 t3 = merge3 t1 t2 t3 && acc in
    t2 = t3 ||
      t1 = t2 ||
      match view t1, view t2, view t3 with
	| C(ct1, ts1), C(ct2, ts2), C(ct3, ts3) when ct1 = ct2 || ct2 = ct3
	    -> fold_left3 m3 true ts1 ts2 ts3
	| _, _, _ -> false
and malign s1 s2 s3 = 
  let rec get_list e s = match s with
    | [] -> raise (Fail "get_list")
    | e' :: s when e = e' -> s
    | _  :: s -> get_list e s in
  let subseq s1 s2 = 
    let rec sloop s1 s2 =
      s1 = [] || match s1 with
	| [] -> true
	| e :: s1 -> sloop s1 (get_list e s2) in
      if List.length s1 > List.length s2
      then false
      else
	if (try sloop s1 s2 with _ -> false)
	then 
	  true
      else 
	false in
  let rec tail_lists acc ls = match ls with
  | [] -> [] :: acc
    | x :: xs -> tail_lists ((x :: xs) :: acc) xs in
  let rec loop s1 s2 s3 = 
    match s1, s2, s3 with
      | s1, [], [] -> true (* the rest of s1 was deleted *)
      | [], [], s3 -> true (* the rest of s3 was added *)
      | [], _ , _  -> subseq s2 s3 (* s2 adds elems iff it is a subseq of s3 *)
      | e1 :: s1', e2 :: s2', e3 :: s3' when e1 = e2 -> 
	  (* e1 = e2 
	     => loop s1' s2' [s3]
	  *)
	  tail_lists [] s3 +> List.fold_left (fun res tl ->
	    loop s1' s2' tl || res) false 
      | e1 :: s1', e2 :: s2', e3 :: s3' when e2 = e3 -> 
	  (* e2 = e3 
	     => loop [s1] 
	  *)
	  tail_lists [] s1 +> List.fold_left (fun res tl ->
	    loop tl s2' s3' || res) false
      | _, _, _ -> false
  in
    loop s1 s2 s3
(*
  let rec get_list e s = match s with
    | [] -> raise (Fail "get_list")
    | e' :: s when e = e' -> s
    | _  :: s -> get_list e s in
  let rec subseq s1 s2 = s1 = [] || match s1 with
    | [] -> true
    | e :: s1 -> try let s' = get_list e s2 in subseq s1 s' with _ -> false
  in
  let rec loop s1 s2 s3 = 
    match s1, s2, s3 with
      | s1, [], [] -> true (* the rest of s1 was deleted *)
      | [], [], s3 -> true (* the rest of s3 was added *)
      | [], _ , _  -> subseq s2 s3 (* s2 adds elems iff it is a subseq of s3 *)
      | e1 :: s1', e2 :: s2', e3 :: s3' -> 
          (* movement vectors: *)
          (** 1,1,1 => no change *)
          (e1 = e2 && e2 = e3 && loop s1' s2' s3') ||
            (** 1,1,0 => either e1,e2 was removed or changed *)
            (e1 = e2 && (loop s1' s2' s3 || loop s1' s2' s3')) ||
            (** 1,0,0 => e1 was removed *)
            (loop s1' s2 s3) ||
            (** 0,1,1 => e2 = e3 is a new elem *)
            (e2 = e3 && loop s1 s2' s3') ||
            (** 0,0,1 => e3 is a new elem *)
            (loop s1 s2 s3')
      | _, _, _ -> false
  in
    loop s1 s2 s3 
*)
and part_of_malign gt1 gt2 gt3 =
  gt1 = gt2 || gt2 = gt3 || 
  (print_endline "[Diff] flattening";
   let f_gt1 = flatten_tree gt1 in
   let l1    = List.length f_gt1 in
   let f_gt2 = flatten_tree gt2 in
   let l2    = List.length f_gt2 in
   let f_gt3 = flatten_tree gt3 in
   let l3    = List.length f_gt3 in
     print_endline ("[Diff] malign "
		     ^ string_of_int l1 ^ " "
		     ^ string_of_int l2 ^ " "
		     ^ string_of_int l3
     );
     print_endline (String.concat " " (f_gt1 +> List.map string_of_gtree'));
     print_endline (String.concat " " (f_gt2 +> List.map string_of_gtree'));
     print_endline (String.concat " " (f_gt3 +> List.map string_of_gtree'));
     let r = malign f_gt1 f_gt2 f_gt3 in
       print_endline "[Diff] return";
       r)

and part_of_edit_dist gt1 gt2 gt3 =
  let dist12 = edit_cost gt1 gt2 in
  let dist23 = edit_cost gt2 gt3 in
  let dist13 = edit_cost gt1 gt3 in
  if dist12 + dist23 < dist13
  then (
    string_of_gtree' gt1 +> print_endline;    
    string_of_gtree' gt2 +> print_endline; 
    string_of_gtree' gt3 +> print_endline;
    ("12: " ^ string_of_int dist12 ^ " 23: " ^ string_of_int dist23 ^ 
    " 13: " ^ string_of_int dist13) +> print_endline;
    (* false *)
    raise (Fail "<")
   )    
  else
    dist12 + dist23 = dist13

(* is up a safe part of the term pair (t, t'') 
 *
 * bp<=(t,t')
 *)
and safe_part up (t, t'') =
  (*
    print_endline "[Diff] safe_part : ";
    print_endline (string_of_diff up);
  *)
  try 
    let t' = apply_noenv up t in
      if !malign_mode
      then 
(* 	part_of_malign t t' t'' (* still too slow *) *)
        part_of_edit_dist t t' t'' 
(*	msa_cost t t' t'' *)
      else 
        merge3 t t' t''
  with (Nomatch | Merge3) -> (
    if !print_abs
    then (
      print_string "[Diff] rejecting:\n\t";
      print_endline (string_of_diff up)
    );
    false)

and relaxed_safe_part up (t, t'') =
  try 
    let t' = apply_noenv up t in
      merge3 t t' t''
  with 
    | Nomatch -> true 
    | Merge3 -> false

(* is the basic patch bp safe with respect to the changeset 
 *
 * bp<=C
 * *)
and safe_part_changeset bp chgset = 
  let safe_f = if !relax then relaxed_safe_part bp else safe_part bp in
    (*
     * List.for_all safe_f chgset
     *)
  let len = List.length (List.filter safe_f chgset) in
    len >= !no_occurs

(* the changeset after application of the basic patch bp; if there is a term to
 * which bp does not apply an exception is raised unless we are in relaxed mode
 * *)
and chop_changeset chgset bp =
  (*  List.map (function (t, t'') -> (t,apply_noenv bp t)) chgset *)
  List.map (function (t, t'') -> (t,safe_apply bp t)) chgset

(* bp <=(t,t) bp' <=> bp'<=(t,t') & bp'(t)=>t'' & bp<=(t,t'') *)
and subpatch_single bp bp' (t, t') =
  safe_part bp' (t, t') &&
    let t'' = apply_noenv bp' t in
      safe_part bp (t, t'')

and subpatch_changeset chgset bp bp' = 
  if safe_part_changeset bp' chgset 
  then
    let chop = chop_changeset chgset bp' in
      if safe_part_changeset bp chop
      then true
      else 
	(
          (*print_string "[Diff] <\n\t";*)
          (*print_endline (string_of_diff bp);*)
          false)
  else 
    (
      (*print_string "[Diff] .\n\t";*)
      (*print_endline (string_of_diff bp');*)
      false
    )
      

and get_ctf_diffs_all work gt1 gt2 =
  let all_pred lhs rhs w u =
    if 
      not(List.mem u w) && 
	match u with UP(a,b) -> not(a = b)
	  then u :: w
	  else w
    in
      traverse (all_pred gt1 gt2) work gt1 gt2

  and get_ctf_diffs_safe work gt1 gt2 =
    let all_pred lhs rhs w u =
      if not(List.mem u w) && 
	(match u with 
      	  | UP(a,b) -> not(a = b)
	  | RM a -> true )
        && safe_part u (gt1, gt2)
      then u :: w
      else w
    in
      traverse (all_pred gt1 gt2) work gt1 gt2

let complete_changeset chgset bp_list =
  let app_f t bp = safe_apply bp t in
    List.for_all
      (function (t,t'') ->
	List.fold_left app_f t bp_list = t''
      )
      chgset

let make_subpatch_tree parts t t' =
  (*let parts = get_ctf_diffs_safe [] t t' in*)
  List.map (function p -> 
    (p, 
    List.filter (function p' -> 
      subpatch_single p' p (t,t')) parts)) 
    parts

(* this function sorts patches according to the subpatch relation in descending
 * order ; notice that when equivalent patches are encountered either could be
 * sorted before the other; it can be the case that two patches in the list are
 * simply not in a subpatch relation to each; then we must find out which one to
 * put first
 *)
let sort_patches chgset parts =
  let comp_patches a b =
    match 
      subpatch_changeset chgset a b, 
      subpatch_changeset chgset b a with
	| true, true -> 0
	| false, true -> -1
	| true, false -> 1
	| false, false -> 0 
            (*
             *(print_string "[Diff] comparing\n\t";
             *print_endline (string_of_diff a);
             *print_string "[Diff] with\n\t";
             *print_endline (string_of_diff b);
             *raise (Fail "incomparable"))
             *)
  in
    List.sort comp_patches parts
      
let make_subpatch_tree_changeset parts chgset =
  let subp = subpatch_changeset chgset in
    (* for each part, find all the parts that are subparts *)
    List.map
      (function bp ->
	(bp, sort_patches chgset  (List.filter (function bp' -> subp bp' bp) parts))
      )
      parts

(* this function takes a list of pairs of patch and subpatches as constructed by
 * make_subpatch_tree_changeset and removes those pairs for which the
 * index-patch is a subpatch of some other
 *)
let filter_subsumed parted =
  let in_subs (bp, _) = List.for_all
    (function (bp' , subs) -> 
      bp = bp' ||
	not(List.mem bp subs
	)) 
    parted in
    List.filter in_subs parted

let string_of_subtree_single (p, ps) =
  ">>> " ^ string_of_diff p ^ "\n" ^
    String.concat " ,\n" (List.map string_of_diff ps)

let string_of_subtree tr = 
  String.concat ";;\n\n" 
    (List.map string_of_subtree_single tr)

(* rejects bp bp'; predicate that decides whether bp rejects bp' with
   respect to term pair (t, t'') *)
let reject_term_pair (t, t'') bp bp' =
  try
    let t' = apply_noenv bp t in
      not(safe_part bp' (t', t''))
  with Nomatch -> (
    print_endline "[Diff] non-applying part?";
    print_endline (string_of_diff bp);
    raise Nomatch
  )

(* apply a bp to all term pairs and return the new pairs *)
let apply_changeset bp chgset =
  let app_f = 
    if !relax 
    then safe_apply
    else apply_noenv in
    List.map (function (t,t'') -> (app_f bp t, t'')) chgset

(* return the list of all those bp' that bp does not reject;
   i.e. which are still applicable AFTER application of bp *)
let get_applicable chgset bp bps =
  try 
    let chgset' = apply_changeset bp chgset in
      (chgset', List.filter (function bp' -> 
	not(chgset' = chgset) &&
	  not(subpatch_changeset chgset' bp' bp) &&
	  safe_part_changeset bp' chgset') bps)
  with Nomatch -> (
    print_endline "[Diff] non-applying part-changeset?";
    print_endline (string_of_diff bp);
    raise Nomatch
  )

let gtree_of_ast_c parsed = Visitor_j.trans_prg2 parsed

let do_option f a =
  match a with 
    | None -> ()
    | Some v -> f v

(* first, let's try to parse a C program with Yoann's parser *)
let read_ast file =
  let (pgm2, parse_stats) = 
    Parse_c.parse_print_error_heuristic file in
    pgm2

let i2s i = string_of_int i
let control_else = mkA("control:else", "Else")
let control_inloop = mkA("control:loop", "InLoop")

let translate_node (n2, ninfo) = match n2 with
  | Control_flow_c2.TopNode -> mkA("phony","TopNode")
  | Control_flow_c2.EndNode -> mkA("phony","EndNode")
  | Control_flow_c2.FunHeader def -> mkC("head:def", [Visitor_j.trans_def def])
  | Control_flow_c2.Decl decl -> Visitor_j.trans_decl decl
  | Control_flow_c2.SeqStart (s,i,info) -> mkA("head:seqstart", "{" ^ i2s i)
  | Control_flow_c2.SeqEnd (i, info) -> mkA("head:seqend", "}" ^ i2s i)
  | Control_flow_c2.ExprStatement (st, (eopt, info)) -> Visitor_j.trans_statement st
  | Control_flow_c2.IfHeader (st, (cond,info)) -> mkC("head:if", [Visitor_j.trans_expr cond])
  | Control_flow_c2.Else info -> control_else
  | Control_flow_c2.WhileHeader (st, (cond, info)) -> mkC("head:while", [Visitor_j.trans_expr cond])
  | Control_flow_c2.DoHeader (st, e, info) -> mkC("head:do", [Visitor_j.trans_expr e])
  | Control_flow_c2.DoWhileTail (expr, info) -> mkC("head:dowhiletail", [Visitor_j.trans_expr expr])
  | Control_flow_c2.ForHeader (st, (((e1opt, _), 
                                   (e2opt, _),
                                   (e3opt, _)),info)) -> mkC("head:for",
							     let handle_empty x = match x with
							       | None -> mkA("expr", "empty")
							       | Some e -> Visitor_j.trans_expr e in
							       [
								 handle_empty e1opt;
								 handle_empty e2opt;
								 handle_empty e3opt;
							       ]) 
  | Control_flow_c2.SwitchHeader (st, (expr, info)) -> mkC("head:switch", [Visitor_j.trans_expr expr])
  | Control_flow_c2.MacroIterHeader (st, 
                                   ((mname, aw2s), info)) ->
      mkC("head:macroit", [mkC(mname, List.map (fun (a,i) -> Visitor_j.trans_arg a) aw2s)])
  | Control_flow_c2.EndStatement info -> mkA("phony", "[endstatement]")

  | Control_flow_c2.Return (st, _) 
  | Control_flow_c2.ReturnExpr (st, _) -> Visitor_j.trans_statement st
      (* BEGIN of TODO

      (* ------------------------ *)
	 | Control_flow_c2.IfdefHeader of ifdef_directive
	 | Control_flow_c2.IfdefElse of ifdef_directive
	 | Control_flow_c2.IfdefEndif of ifdef_directive
         

      (* ------------------------ *)
	 | Control_flow_c2.DefineHeader of string wrap * define_kind

	 | Control_flow_c2.DefineExpr of expression 
	 | Control_flow_c2.DefineType of fullType
	 | Control_flow_c2.DefineDoWhileZeroHeader of unit wrap

	 | Control_flow_c2.Include of includ

      (* obsolete? *)
	 | Control_flow_c2.MacroTop of string * argument wrap2 list * il 

      (* ------------------------ *)


  *)
	 | Control_flow_c2.Default (st, _) ->
	     mkA("head:default", "default")
	 | Control_flow_c2.Case (st,(e,_)) -> 
	     mkC("head:case", [Visitor_j.trans_expr e])
	 | Control_flow_c2.CaseRange (st, ((e1, e2), _ )) ->
	     mkC("head:caserange", [Visitor_j.trans_expr e1; 
				    Visitor_j.trans_expr e2])
	 | Control_flow_c2.Continue (st,_) 
	 | Control_flow_c2.Break    (st,_) 
   (*
      (* no counter part in cocci *)

*)
	 | Control_flow_c2.Goto (st, _) -> Visitor_j.trans_statement st
	 | Control_flow_c2.Label (st, (lab, _)) -> mkA("head:label", lab)
(*

	 | Control_flow_c2.Asm of statement * asmbody wrap
	 | Control_flow_c2.MacroStmt of statement * unit wrap

      (* ------------------------ *)
      (* some control nodes *)

	 END of TODO *)

  | Control_flow_c2.Enter -> mkA("phony", "[enter]")
  | Control_flow_c2.Exit -> mkA("phony", "[exit]")
  | Control_flow_c2.Fake -> mkA("phony", "[fake]")

  (* flow_to_ast: In this case, I need to know the  order between the children
   * of the switch in the graph. 
   *)
  | Control_flow_c2.CaseNode i -> mkA("phony", "[case" ^ i2s i ^"]")

  (* ------------------------ *)
  (* for ctl:  *)
  | Control_flow_c2.TrueNode -> mkA("phony", "[then]")
  | Control_flow_c2.FalseNode -> mkA("phony", "[else]")
  | Control_flow_c2.InLoopNode (* almost equivalent to TrueNode but just for loops *) -> 
      control_inloop
      (* mkA("phony", "InLoop") *)
  | Control_flow_c2.AfterNode -> mkA("phony", "[after]")
  | Control_flow_c2.FallThroughNode -> mkA("phony", "[fallthrough]")

  | Control_flow_c2.ErrorExit -> mkA("phony", "[errorexit]")
  | _ -> mkA("NODE", "N/A")

let print_gflow g =
  let pr = print_string in
    pr "digraph misc {\n" ;
    pr "size = \"10,10\";\n" ;

    let nodes = g#nodes in
      nodes#iter (fun (k,gtree) -> 
	(* so can see if nodes without arcs were created *) 
	let s = string_of_gtree' gtree in
	  pr (Printf.sprintf "%d [label=\"%s   [%d]\"];\n" k s k)
      );

      nodes#iter (fun (k,node) -> 
	let succ = g#successors k in
	  succ#iter (fun (j,edge) ->
            pr (Printf.sprintf "%d -> %d;\n" k j);
	  );
      );
      pr "}\n" ;
      ()

let add_node i node g = g#add_nodei i node

(* convert a graph produced by ast_to_flow into a graph where all nodes in the
 * flow have been translated to their gtree counterparts
 *)
let flow_to_gflow flow =
  let gflow = ref (new Ograph_extended.ograph_mutable) in
  let nodes = flow#nodes in
    nodes#iter (fun (index, (node1, s)) ->
      !gflow +> add_node index (translate_node node1);
    );
    nodes#iter (fun (index, node) ->
      let succ = flow#successors index in
	succ#iter (fun (j, edge_val) -> 
          !gflow#add_arc ((index,j), edge_val)
        )
    );
    !gflow


let read_ast_cfg file =
  v_print_endline "[Diff] parsing...";
  let (pgm2, parse_stats) = 
    Parse_c.parse_print_error_heuristic file in
    (*  let flows = List.map (function (c,info) -> Ast_to_flow2.ast_to_control_flow c) pgm2 in *)
    (* ast_to_control_flow is given a toplevel entry and turns that into a flow *)
    v_print_endline "[Diff] type annotating";
    let tops_envs = 
      pgm2 +> List.map fst +>
	Type_annoter_c.annotate_program 
	!Type_annoter_c.initial_env
    in
    let flows = tops_envs +> List.map (function (c,info) -> Ast_to_flow2.ast_to_control_flow c)  in
    let  gflows = ref [] in
      flows +> List.iter (do_option (fun f -> 
				       gflows := (flow_to_gflow f) :: !gflows));
      (* among the gflows constructed filter out those that are not flows for a
       * function definition
       *)
      (pgm2, !gflows +> List.filter (function gf -> 
				       gf#nodes#tolist +> List.exists (
					 function (i,n) -> match view n with
					   | C("head:def",[{node=C("def",_)}]) -> true
					   | _ -> false)
				    ))

type environment = (string * gtree) list
type res = {last : gtree option; skip : int list ; env : environment}
type res_trace = {last_t : gtree option; skip_t : int list; env_t : environment ; trace : int list}

let print_environment env =
  List.iter (function (x, v) ->
    print_string " ;";
    print_string (x ^ " -> " ^ string_of_gtree' v);
  ) env; print_newline ()

let bind env (x, v) = 
  try match List.assoc x env with
    | v' when not(v=v') -> raise (Match_failure ("Diff.bind: " ^
						    x ^ " => " ^
						    string_of_gtree' v ^ " != " ^
						    string_of_gtree' v' , 1232, 0))
    | _ -> env
  with Not_found -> (x,v) :: env

let string_of_bind string_of_val (x, v) = 
  "(" ^ x ^ "->" ^ string_of_val v ^ ")"

let string_of_env env = 
  String.concat "; " (List.map (string_of_bind string_of_gtree') env)

let extend_env env1 env2 =
  List.fold_left bind env1 env2
let ddd = mkA("SKIP", "...")
let (%%) e1 e2 = extend_env e1 e2
let (=>) (k,v) env = bind env (k,v)
let get_val n g = g#nodes#find n
let get_succ n g = (g#successors n)#tolist
let get_next_vp'' g vp n = 
  List.rev_map fst (get_succ n g) 
    (* below we filter those, that have already be visited
       let ns = get_succ n g in
       List.fold_left (fun acc_n (n',_) -> 
       if not(List.mem n' vp.skip)
       then n' :: acc_n
       else acc_n) [] ns
    *)


type skip_action = SKIP | LOOP | FALSE | ALWAYSTRUE

let is_error_exit t = match view t with
    (*  | A("phony", "[errorexit]") -> true *)
  | A("phony", "[after]") -> true
  | _ -> false

let string_of_pattern p =
  let loc p = match view p with
    | C("CM", [t]) -> string_of_gtree' t
    | skip when skip == view ddd -> "..."
    | gt -> raise (Match_failure (string_of_gtree' p, 1263,0)) in
    String.concat " " (List.map loc p)

exception ErrorSpec

let cont_match_spec spec g cp n =
  let init_vp = {skip = []; env = []; last = None;} in 
  let matched_vp vp n env = 
    (* let f, env' = try true, env %% vp.env with Bind_error -> false, [] in *)
    (* in this semantic, we never allow visiting the same node twice *)
    let f, env' = try 
	not(List.mem n vp.skip) && 
	  not(List.exists (function nh -> get_val nh g = get_val n g ) vp.skip)
	  , env %% vp.env with Match_failure _ -> false, [] in
      f, {last = Some (get_val n g); skip = n :: vp.skip; env = env'} in
  let skipped_vp vp n = {
    last = vp.last;
    skip = n :: vp.skip; 
    env = vp.env} in
  let check_vp vp n  = 
    let t_val = get_val n g in
      if Some t_val = vp.last
      then FALSE 
      else if List.mem n vp.skip
      then (
	(* print_endline ("[Diff] LOOP on " ^ 
           string_of_int n); *)
	LOOP)
      else if is_error_exit t_val 
      then ALWAYSTRUE
      else SKIP
  in
  let rec trans_cp cp c = match cp with
    | [] -> c
    | bp :: cp -> trans_bp bp (trans_cp cp c)
  and trans_bp bp c vp n = match view bp with
    | C("CM", [gt]) ->
	(try 
            let env = spec gt (get_val n g) in
            let f,vp' = matched_vp vp n env in
              f && List.for_all (function (n',_) -> c vp' n') (get_succ n g)
	  with Nomatch -> false)
    | _ when bp == ddd ->
	c vp n || (
          match check_vp vp n with
            | FALSE -> false
            | LOOP -> true
            | SKIP -> 
		let ns = get_next_vp'' g vp n in
                  not(ns = []) &&
		    ns +> List.exists (function n' -> not(n = n'))
                  &&
                    let vp' = skipped_vp vp n in
                      List.for_all (trans_bp ddd c vp') ns
	    | ALWAYSTRUE -> true
	)
  in
  let matcher = trans_cp cp (fun vp x -> true) in
    try matcher init_vp n with ErrorSpec -> false

let find_embedded_succ g n p =
  let spec pat t = if find_match pat t then [] else raise ErrorSpec in
  let ns = (g#successors n)#tolist in
    if ns = []
    then (print_endline ("[Diff] term: " ^ string_of_gtree' (get_val n g) ^ " has no successors");
	  true)
    else 
      List.for_all (function (n, _) -> cont_match_spec spec g [ddd; mkC("CM", [p])] n) ((g#successors n)#tolist)


let cont_match g cp n = 
  (*
    print_endline ("[Diff] checking pattern : " ^ 
    string_of_pattern cp);
  *)
  let init_vp = {skip = []; env = []; last = None;} in 
  let matched_vp vp n env = 
    (* let f, env' = try true, env %% vp.env with Bind_error -> false, [] in *)
    (* in this semantic, we never allow visiting the same node twice *)
    let f, env' = try 
	not(List.mem n vp.skip) && 
	  not(List.exists (function nh -> get_val nh g = get_val n g ) vp.skip)
	  , env %% vp.env with Match_failure _ -> false, [] in
      f, {last = Some (get_val n g); skip = n :: vp.skip; env = env'} in
  let skipped_vp vp n = {
    last = vp.last;
    skip = n :: vp.skip; 
    env = vp.env} in
  let check_vp vp n  = 
    let t_val = get_val n g in
      if Some t_val = vp.last
      then FALSE 
      else if List.mem n vp.skip
      then (
	(* print_endline ("[Diff] LOOP on " ^ 
           string_of_int n); *)
	LOOP)
      else if is_error_exit t_val 
      then ALWAYSTRUE
      else SKIP
  in
  let rec trans_cp cp c = match cp with
    | [] -> c
    | bp :: cp -> trans_bp bp (trans_cp cp c)
  and trans_bp bp c vp n = match view bp with
    | C("CM", [gt]) ->
	(try 
            (* let env = match_term gt (get_val n g) in *)
            let envs = find_nested_matches gt (get_val n g) in
              List.exists (function env ->
		let f,vp' = matched_vp vp n env in
		  f && List.for_all (function (n',_) -> c vp' n') (get_succ n g)) envs
	  with Nomatch -> false)
    | _ when bp == ddd ->
	c vp n || (
          match check_vp vp n with
            | FALSE -> false
            | LOOP -> true
            | SKIP -> 
		let ns = get_next_vp'' g vp n in
                  not(ns = []) &&
                    ns +> List.exists (function n' -> not(n = n')) &&
                    let vp' = skipped_vp vp n in
                      List.for_all (trans_bp ddd c vp') ns
	    | ALWAYSTRUE -> true
	)
    | _ -> raise (Match_failure (string_of_gtree' bp, 1429,0))
  in
  let matcher = trans_cp cp (fun vp x -> true) in
    matcher init_vp n

let traces_ref = ref []
let count = ref []
let print_trace tr =
  print_string ("[Diff] " ^ string_of_int (List.length tr) ^ ": ");
  tr +> List.iter 
    (function i_list -> 
      print_string ("<" ^ List.length i_list +> string_of_int ^ ">");
      print_string "[[ ";
      i_list 
      +> List.map string_of_int
      +> String.concat " > "
      +> print_string;
      print_string "]] "
    );
  print_newline ()



let cont_match_traces  g cp n = 
  (*
    print_endline ("[Diff] checking pattern : " ^ 
    string_of_pattern cp);
  *)
  let init_vp = {skip_t = []; env_t = []; last_t = None; trace = []} in 
  let matched_vp vp n env = 
    (* let f, env' = try true, env %% vp.env with Bind_error -> false, [] in *)
    (* in this semantic, we never allow visiting the same node twice *)
    let f, env' = try 
	not(List.mem n vp.skip_t) && 
	  not(List.exists (function nh -> get_val nh g = get_val n g ) vp.skip_t)
	  , env %% vp.env_t with Match_failure _ -> false, [] in
      f, {last_t = Some (get_val n g); skip_t = n :: vp.skip_t; env_t = env'; trace = n :: vp.trace} in
  let skipped_vp vp n = {
    last_t = vp.last_t;
    skip_t = n :: vp.skip_t; 
    env_t = vp.env_t;
    trace = vp.trace;
  } in
  let check_vp vp n  = 
    let t_val = get_val n g in
      if Some t_val = vp.last_t
      then FALSE 
      else if List.mem n vp.skip_t
      then (
	(* print_endline ("[Diff] LOOP on " ^ 
           string_of_int n); *)
	LOOP)
      else if is_error_exit t_val 
      then ALWAYSTRUE
      else SKIP
  in
  let rec trans_cp cp c = match cp with
    | [] -> c
    | bp :: cp -> trans_bp bp (trans_cp cp c)
  and trans_bp bp c vp n = match view bp with
    | C("CM", [gt]) ->
	(try 
            (* let env = match_term gt (get_val n g) in *)
            let envs = find_nested_matches gt (get_val n g) in
              List.exists (function env ->
		let f,vp' = matched_vp vp n env in
		  f && List.for_all (function (n',_) -> c vp' n') (get_succ n g)) envs
	  with Nomatch -> false)
    | _ when bp == ddd ->
	c vp n || (
          match check_vp vp n with
            | FALSE -> false
            | LOOP -> true
            | SKIP -> 
		let ns = get_next_vp'' g vp n in
                  not(ns = []) &&
                    ns +> List.exists (function n' -> not(n = n'))
                  &&
                    let vp' = skipped_vp vp n in
                      List.for_all (trans_bp ddd c vp') ns
	    | ALWAYSTRUE -> true
	)
    | _ -> raise (Match_failure (string_of_gtree' bp, 1429,0))
  in
  let matcher = 
    trans_cp cp (fun vp x -> 
      traces_ref := List.rev (vp.trace) :: !traces_ref; (* recall that indices come in reverse order *)
      count := [1] :: !count;
      true) in
    matcher init_vp n 

      
let get_traces g sp n =
  traces_ref := [];
  if 
    cont_match_traces g sp n
  then (
    let v = !traces_ref in (
      traces_ref := []; 
      Some v)
  )
  else 
    None

let valOf x = match x with
  | None -> raise (Fail "valOf: None")
  | Some y -> y


let get_last_locs g cp n =
  let loc_list = ref [] in
  let init_vp = {skip = []; env = []; last = None;} in 
  let matched_vp vp n env = 
    (* let f, env' = try true, env %% vp.env with Bind_error -> false, [] in *)
    (* in this semantic, we never allow visiting the same node twice *)
    let f, env' = try not(List.mem n vp.skip), env %% vp.env with Match_failure _ -> false, [] in
      f, {last = Some (get_val n g); skip = n :: vp.skip; env = env'} in
  let skipped_vp vp n = {
    last = vp.last;
    skip = n :: vp.skip; 
    env = vp.env} in
  let check_vp vp n  = not(List.mem n vp.skip) && 
    not(Some (get_val n g) = vp.last)
  in
  let rec trans_cp cp c = match cp with
    | [] -> c
    | bp :: cp -> trans_bp bp (trans_cp cp c)
  and trans_bp bp c vp n = match view bp with
    | C("CM", [gt]) ->
	(try 
            let env = match_term gt (get_val n g) in
            let f,vp' = matched_vp vp n env in
              f && List.for_all (function (n',_) -> c vp' n') (get_succ n g)
	  with Nomatch -> false)
    | _ when bp == ddd ->
	c vp n || (
          check_vp vp n &&
            let ns = get_next_vp'' g vp n in
              not(ns = []) &&
		let vp' = skipped_vp vp n in
		  List.for_all (trans_bp ddd c vp') ns
	)
  in
  let matcher = trans_cp cp (fun vp x -> 
    loc_list := valOf vp.last :: !loc_list;
    true) in
    if matcher init_vp n
    then Some (List.fold_left (fun acc_l e -> 
      if List.mem e acc_l
      then acc_l
      else e :: acc_l
    ) [] !loc_list)
    else None

let safe up tup = 
  match tup with
    | UP (o, n) -> (try 
	  debug_msg ("applying : \n" ^
			string_of_diff tup);
	match apply_noenv up o = n with
	  | true -> debug_msg "good"; true
	  | false -> debug_msg "bad"; false
      with Nomatch -> debug_msg "N/M"; true)
    | _ -> raise (Fail "tup not supported")


exception No_abs


let rec free_vars t =
  let no_dub_app l1 l2 = List.rev_append 
    (List.filter (fun x -> not(List.mem x l2)) l1)
    l2 
  in
    match view t with
      | A ("meta", mvar) -> [mvar]
      | C (_, ts) -> List.fold_left
	  (fun fvs_acc t -> no_dub_app (free_vars t) fvs_acc)
	    [] ts
      | _ -> []

let rec count_vars t =
  match view t with
    | A("meta", _) -> 1
    | C(_, ts) -> List.fold_left
	(fun var_count t -> count_vars t + var_count) 0 ts
    | _ -> 0

(* assume only RELATED terms are given as arguments; this should hold a the
 * function is only called from make_compat_pairs which is always called on
 * related terms (somehow?)
 *)
let compatible_with lhs rhs =
  let fv_l = free_vars lhs in
  let fv_r = free_vars rhs in
    if fv_r = []
    then debug_msg "fv_r = []";
    (*
     *let b = subset fv_r fv_l in
     *if b && fv_r = [] then debug_msg "compat and empty";
     *b
     *)
    (* strict compatibility: equal metas *)
    if !be_strict
    then subset fv_r fv_l && subset fv_l fv_r
      (* loose compatibility: lhs <= rhs *)
    else subset fv_r fv_l

let make_compat_pairs lhs rhs_list acc =
  List.fold_left (fun pairs rhs ->
    if compatible_with lhs rhs
    then UP (lhs, rhs) :: pairs
    else pairs
  ) acc rhs_list

let make_gmeta name = mkA ("meta", name)

let metactx = ref 0
let reset_meta () = metactx := 0
let inc x = let v = !x in (x := v + 1; v)
let ref_meta () = inc metactx
let mkM () = mkA("meta", "X" ^ ref_meta() +> string_of_int)
let new_meta env t =
  let m = "X" ^ string_of_int (ref_meta ()) in
    (*print_endline *)
    (*("binding " ^ m ^ "->" ^ *)
    (*string_of_gtree str_of_ctype str_of_catom t);*)
    [make_gmeta m], [(m,t)]
let is_meta v = match view v with | A("meta", _) -> true | _ -> false

let get_metas build_mode org_env t = 
  let rec loop env =
    match env with
      | [] when build_mode -> (
          debug_msg ("bind: " ^ string_of_gtree str_of_ctype str_of_catom t);
          debug_msg (">>>>>>>>>>> with size: " ^ string_of_int (gsize t));
          new_meta org_env t)
      | [] -> [], []
      | (m, t') :: env when t = t' ->
          (* below we assume that equal terms need not be abstracted by equal
           * meta-variables
           *)
          if !use_mvars
          then
            let metas, env' = loop env in
              (make_gmeta m) :: metas, (m, t') :: env'
		(* below we make sure that equal terms are abstracted by the SAME
		 * meta-variabel; so once we find one reverse binding to t, we can
		 * return the corresponding metavariable and need not look any further
		 *)
          else
            [make_gmeta m], org_env
      | b :: env ->
          let metas, env' = loop env in
            if build_mode
            then metas, b :: env'
            else metas, org_env

  in
    loop org_env

let rec prefix a lists =
  (*print_endline ("prefixing " ^*)
  (*string_of_gtree str_of_ctype str_of_catom a);*)
  match lists with(*{{{*)
    | [] -> []
    | lis :: lists -> (a :: lis) :: prefix a lists(*}}}*)

let rec prefix_all lis lists =
  match lis with(*{{{*)
    | [] -> []
    | elem :: lis -> (prefix elem lists) @ prefix_all lis lists(*}}}*)
	
let rec gen_perms lists =
  (*
   *print_endline "gen_perms sizes: ";
   *List.iter (fun ec ->
   * print_string "<";
   * print_string (string_of_int (List.length ec));
   * print_string "> ";
   * ) lists;
   *)
  (*print_newline ();*)
  (* FIXME: figure out why this assertion was put here in the first place *)
  (*assert(not(List.exists ((=) []) lists));*)
  (*debug_msg "perms of ";*)
  (*List.iter (fun l -> List.iter (fun e -> debug_msg ((string_of_gtree*)
  (*str_of_ctype str_of_catom e) ^ " ")) l; debug_msg "%%") lists;*)
  match lists with(*{{{*)
    | [] -> (debug_msg "."; [[]])
    | lis :: lists -> (debug_msg ","; prefix_all lis (gen_perms lists))(*}}}*)


(*
  let rec abs_term_size terms_changed is_fixed should_abs up =
  let rec loop build_mode env t = match t with
  | A (ct, at) -> 
  if is_fixed t
  then 
  if terms_changed t
  then [t], env
  else 
  let metas, renv = get_build_mode env t in
  t :: metas, renv
  else 
  if not(should_abs t)
  then [t], env
  else 
(* now we have an atomic term that we should abstract and thus we will
  * not also return the concrete term as a possibility; the problem is
  * that then we may abstract atoms which should not have been because
  * they were actually changed -- for those atoms that change, we
  * therefore return both the concrete term and an abstracted one
*)
  if terms_changed t
  then
(*[t], env*)
  let metas, renv = get_metas build_mode env t in
  t :: metas, renv
  else 
  get_metas build_mode env t (*}}}*)
  | C (ct, []) -> raise (Fail "whhaaattt")
  | C (ct, ts) ->
  debug_msg ("CC: " ^ string_of_gtree str_of_ctype str_of_catom t);(*{{{*)
  if !abs_subterms <= gsize t
  then [t], env
  else
  let metas, env = 
  if not(is_fixed t) && (if build_mode then should_abs t else true)
  then
  get_metas build_mode env t 
  else 
(* the term is fixed, but it did not change "by itself" so we should
  * actually abstract it
*)
  if terms_changed t
  then
  [], env 
  else 
  get_metas build_mode env t
  in
  let ts_lists, env_ts = List.fold_left
  (fun (ts_lists_acc, acc_env) tn ->
(* each abs_tns is a list of possible abstractions for the term tn
  * and env_n is the new environment (for build_mode)
*)
  let abs_tns, env_n = 
(*if not(is_fixed tn)*)
(*then*)
  loop build_mode acc_env tn 
(*else*)
(*[tn], acc_env*)
  in
  let abs_tns = if abs_tns = [] then [tn] else abs_tns in
  abs_tns :: ts_lists_acc, env_n
  ) ([], env) (List.rev ts) in
(* note how we reverse the list ts given to the fold_left function above
  * to ensure that subterms are visited in left-to-right order and
  * inserted in left-to-right order
*)
(* ts_lists is a list of lists of possible abstractions of each 
  * term in ts we now wish to generate a new list of lists such 
  * that each list in this new list contains one element from 
  * each of the old lists in the same order
*)
(*print_string "input size to gen_perms: ";*)
(*print_endline (string_of_int (List.length ts_lists));*)
(*List.iter (fun l ->*)
(*print_string ("<" ^ string_of_int (List.length l) ^ "> ");*)
(*if List.length l > 128 then raise (Fail "not going to work")*)
(*List.iter (fun gt -> print_endline (string_of_gtree' gt)) l;*)
(*flush stdout;*)
(* ) ts_lists;*)
(*print_newline ();*)
  let perms = gen_perms ts_lists in
(* given the perms we now construct the complete term C(ct,arg) *)
  let rs = List.rev (List.fold_left (fun acc_t args -> 
  C(ct, args) :: acc_t) [] perms) in
(* finally, we return the version of t where sub-terms have been
  * abstracted as well as the possible metas that could replace t
*)
  metas @ rs, env_ts in(*}}}*)
  match up with 
  | UP(lhs, rhs) -> 
(* first build up all possible lhs's along with the environment(*{{{*)
  * that gives bindings for all abstracted variables in lhs's
*)
  reset_meta ();
(*print_endline ("loop :: \n" ^ string_of_diff up);*)
  let abs_lhss, lhs_env = loop true [] lhs in
(*List.iter (fun (m,t) -> print_string*)
(*("[" ^ m ^ "~>" ^ string_of_gtree' t ^ "] ")) lhs_env;*)
(*print_newline ();*)
(*print_endline ("lhss : " ^ string_of_int (List.length abs_lhss));*)
(*print_endline "lhss = ";*)
(*List.iter (fun d -> print_endline (string_of_gtree' d)) abs_lhss;*)
  assert(not(abs_lhss = []));
(* now we check that the only solution is not "X0" so that we will end
  * up transforming everything into whatever rhs
*)
  let abs_lhss = (match abs_lhss with
  | [A ("meta", _) ] -> (debug_msg 
  ("contextless lhs: " ^ string_of_diff up); [lhs])
  | _ -> abs_lhss)
(* now use the environment to abstract the rhs term
*) in
  let abs_rhss, rhs_env = loop false lhs_env rhs in
(*print_endline ("rhss : " ^ string_of_int (List.length abs_rhss));*)
(*print_endline "rhss = ";*)
(*List.iter (fun d -> print_endline (string_of_gtree' d)) abs_rhss;*)
(*List.iter (fun (m,t) -> print_string*)
(*("[" ^ m ^ "~>" ^ string_of_gtree' t ^ "] ")) rhs_env;*)
(*print_newline ();*)
(* if the below assertion fails, there is something wrong with the
  * environments generated
*)
(*assert(lhs_env = rhs_env);*)
(* we now wish to combine each abs_lhs with a compatible abs_rhs
*)
(* if the rhs had no possible abstractions then we return simply the
  * original rhs; this can not happen for lhs's as the "bind" mode is
  * "on" unless the fixed_list dissallows all abstractions
*)
  let abs_rhss = if abs_rhss = [] then [rhs] else abs_rhss in
  let lres = List.fold_left (fun pairs lhs ->
  make_compat_pairs lhs abs_rhss pairs
  ) [] abs_lhss
  in
  lres, lhs_env (* = rhs_env *)(*}}}*)
  | _ -> raise (Fail "non supported update given to abs_term")

*)

let renumber_metas t metas =
  match view t with
    | A ("meta", mvar) -> (try 
    	  let v = List.assoc mvar metas in
  	    mkA ("meta", v), metas
      with _ -> 
        let nm = "X" ^ string_of_int (ref_meta ()) in
	  mkA ("meta", nm), (mvar, nm) :: metas)
    | _ -> t, metas

let fold_botup term upfun initial_result =
  let rec loop t acc_result =
    match view t with
      | A _ -> upfun t acc_result
      | C (ct, ts) -> 
          let new_terms, new_acc_result = List.fold_left
            (fun (ts, acc_res) t ->
              let new_t, new_acc = loop t acc_res in
          	new_t :: ts, new_acc
            ) ([], acc_result) ts
          in
            upfun (mkC(ct, List.rev new_terms)) new_acc_result
  in
    loop term initial_result

let renumber_metas_up up =
  (*print_endline "[Diff] renumbering metas";*)
  reset_meta ();
  match up with
    | UP(lhs, rhs) -> 
	let lhs_re, lhs_env = fold_botup lhs renumber_metas [] in
      	let rhs_re, rhs_env = fold_botup rhs renumber_metas lhs_env in
	  assert(lhs_env = rhs_env);
	  UP(lhs_re, rhs_re)
    | ID s -> 
	let nm, new_env = renumber_metas s [] in ID nm
    | RM s -> 
      	let nm, new_env = renumber_metas s [] in RM nm
    | ADD s -> 
      	let nm, new_env = renumber_metas s [] in ADD nm

let rec abs_term_imp terms_changed is_fixed up =
  let cur_depth = ref !abs_depth in
  let should_abs t = 
     !cur_depth >= 0 
    (* if !cur_depth >= 0 *)
    (* (\* then (print_endline ("[Diff] allowed at depth: " ^ string_of_int !cur_depth); true) *\) *)
    (* (\* else (print_endline ("[Diff] not allowed at depth " ^ string_of_int !cur_depth); false) *\) *)
    (* then (print_endline ("[Diff] allowing " ^ string_of_gtree' t); true) *)
    (* else ( *)
    (*   print_endline ("[Diff] current depth " ^ string_of_int !cur_depth); *)
    (*   print_endline (string_of_gtree' t); *)
    (*   false) *)
  in
  let rec loop build_mode env t = 
    match view t with
    | _ when !cur_depth <= 0 -> get_metas build_mode env t
    | A (ct, at) -> 
	if should_abs t
	then
          if terms_changed t
          then
            let metas, renv = get_metas build_mode env t in
              t :: metas, renv
		(*[t], env*)
	  else
	    if is_fixed t
	    then
              let metas, renv = get_metas build_mode env t in
		t :: metas, renv
            else 
              get_metas build_mode env t
	else (
          print_endline ("[Diff] not abstracting atom: " ^ string_of_gtree' t);
          [t], env)
    | C (ct, []) -> 
	(* raise (Fail ("whhaaattt: "^ct^"")) *)
	(* this case has been reached we could have an empty file;
	 * this can happen, you know! we return simply an atom
	 *)
	[mkA(ct, "new file")], env
    | C("prg", _)
    | C("prg2", _)
    | C("def",_) 
    | C("comp{}", _) 
    | C("if", _) 
    | C("while", _)
    | C("dowhile", _)
    | C("for", _) 
    | C("switch", _) 
    | C("comp{}", _)
    | C("storage", _) -> [t], env
    (* | C (ct, ts) when !abs_subterms <= zsize t ->  *)
    (* 	(fdebug_endline !print_abs ("[Diff] abs_subterms " ^ string_of_gtree' t); *)
    (* 	 [t], env) *)
    | C("call", f :: ts) ->
	cur_depth := !cur_depth - 1;
        (* generate abstract versions for each t ∈ ts *)
        let meta_lists, env_acc =
          List.fold_left (fun (acc_lists, env') t -> 
			    let meta', env'' = loop build_mode env' t
			    in (meta' :: acc_lists), env''
                         ) ([], env) ts in
          (* generate all permutations of the list of lists *)
        let meta_perm = gen_perms (List.rev meta_lists) in
          (* construct new term from lists *)
	  cur_depth := !cur_depth + 1;
          t :: List.rev (List.fold_left (fun acc_meta meta_list ->
					   mkC("call", f :: meta_list) :: acc_meta
                                        ) [] meta_perm), env_acc
    | C (ct, ts) ->
	let metas, env = 
          if should_abs t && not(terms_changed t)
          then get_metas build_mode env t 
          else [], env
	in
	  cur_depth := !cur_depth - 1;
	  let ts_lists, env_ts = List.fold_left
            (fun (ts_lists_acc, acc_env) tn ->
              let abs_tns, env_n = loop build_mode acc_env tn 
              in
              let abs_tns = if abs_tns = [] then [tn] else abs_tns in
		abs_tns :: ts_lists_acc, env_n) 
            ([], env) (List.rev ts) 
	  in
	    cur_depth := !cur_depth + 1;
	    let perms = gen_perms ts_lists in
	    let rs = List.rev (List.fold_left (fun acc_t args -> 
              mkC(ct, args) :: acc_t) [] perms) 
	    in
              metas @ rs, env_ts in(*}}}*)
    match up with 
      | UP(lhs, rhs) -> 
	  (* first build up all possible lhs's along with the environment(*{{{*)
	   * that gives bindings for all abstracted variables in lhs's
	   *)
	  reset_meta ();
	  (*print_endline ("loop :: \n" ^ string_of_diff up);*)
	  let abs_lhss, lhs_env = loop true [] lhs in
	    assert(not(abs_lhss = []));
	    (* now we check that the only solution is not "X0" so that we will end
             * up transforming everything into whatever rhs
             *)
	    let abs_lhss = (match abs_lhss with
	      | [{node=A ("meta", _)}] -> 
		  (debug_msg 
		      ("contextless lhs: " ^ string_of_diff up); [lhs]
		  )
	      | _ -> abs_lhss)
	      (* now use the environment to abstract the rhs term
	      *) in
	    let abs_rhss, rhs_env = loop false lhs_env rhs in
	      (* we now wish to combine each abs_lhs with a compatible abs_rhs
	      *)
	      (* if the rhs had no possible abstractions then we return simply the
	       * original rhs; this can not happen for lhs's as the "bind" mode is
	       * "on" unless the fixed_list dissallows all abstractions
	       *)
	    let abs_rhss = if abs_rhss = [] then [rhs] else abs_rhss in
	    let lres = List.fold_left (fun pairs lhs ->
	      make_compat_pairs lhs abs_rhss pairs
            ) [] abs_lhss
	    in
	      lres, lhs_env (* = rhs_env *)(*}}}*)
      | _ -> raise (Fail "non supported update given to abs_term_size_imp")


let abs_term_noenv terms_changed is_fixed should_abs up = 
  fdebug_endline !print_abs ("[Diff] abstracting concrete update with size: " ^
				string_of_int (Difftype.fsize up) ^ "\n" ^
				string_of_diff up);
  (*let res, _ = abs_term_size terms_changed is_fixed should_abs up in *)
  let res, _ = abs_term_imp terms_changed is_fixed up in 
  let res_norm = List.map renumber_metas_up res in
    fdebug_endline !print_abs ("[Diff] resulting abstract updates: " ^ 
				  string_of_int (List.length res));
    if !print_abs 
    then List.iter (function d -> print_endline (string_of_diff d)) res_norm;
    res_norm

(* according to this function a term is fixed if it occurs in a given list
 * the assumption is that this list have been constructed by a previous
 * analysis, eg. datamining of frequent identifiers
 * if it does not occur and is an atom, then it is not fixed
 * if it does not occur and is an "appliction" and the op. does 
 * occur, then it is fixed
 * otherwise it is not fixed, even though it does not occur
 *)
let list_fixed flist t =
  if !be_fixed
  then List.mem t flist 
  else false
    (*
     *||
     *match t with
     *| A _ -> false
     *| C (_, op :: args) when List.mem op flist -> true
     *| C (_, op :: args) -> true
     *| _ -> false
     *)

(* this function always allows abstraction when the term is not fixed
 * one could maybe imagine more complex cases, where even though a term
 * is not fixed one would rather not abstract it; one example is that for very
 * large complex terms that are not frequent; very large terms could be
 * considered inappropriate for abstraction as we are not interested in finding
 * very large common structures, but are mostly concerned about smaller things;
 * at least we can make the decision be up to the user by defining a threshold
 * as to how large terms we allow to be abstracted
 *)

let should_abs_always t = true

(* depth based abstraction pred: only abstract "shallow" terms -- i.e. terms
 * with depth less than threshold
 *)
let should_abs_depth t = gdepth t <= !abs_depth


let non_dub_cons x xs = if List.mem x xs then xs else x :: xs 
let (%%) a b = non_dub_cons a b
let non_dub_app ls1 ls2 = List.fold_left (fun acc l -> l %% acc) ls1 ls2
let (%) ls1 ls2 = non_dub_app ls1 ls2

(* construct all the possible sub-terms of a given term in the gtree format; the
 * resulting list does not have any order that one should rely on
 *)
let make_all_subterms t =
  let rec loop ts t =
    match view t with
      | C(_, ts_sub) -> List.fold_left loop (t %% ts) ts_sub
      | _ -> t %% ts in
    loop [] t

(* in order to make a list of the things that are supposed to be fixed when
 * doing abstraction, we need a list of (org,up) programs to work with;
 * the idea is to use datamining to find a subset of items that occurs
 * frequently and use that to construct the fixed_list
 *)

let select_max a b =
  if List.length a > List.length b
  then a
  else b
let union_lists unioned_list new_list =
  new_list % unioned_list

let unique l =
  let len = List.length l in
  let tbl = Hashtbl.create (len) in
    print_endline ("[Diff] inserting " ^ 
		      string_of_int len ^ " elements");
    let lct = ref 0 in
      List.iter (fun i -> 
	Hashtbl.replace tbl i ();
	debug_msg (string_of_int !lct);
	lct := !lct + 1
      ) l;
      print_endline ("[Diff] extracting " ^ 
			string_of_int (Hashtbl.length tbl) ^ " elements");
      Hashtbl.fold (fun key data accu -> key :: accu) tbl []

let always_dive lhs rhs = 
  match lhs, rhs with
    | C (_,_), C (_,_) -> true
    | _ -> false

let no_calls_dive lhs rhs = 
  match lhs, rhs with
    | C("call", f::_), C("call", f'::_) -> (debug_msg "$"; false)
    | C (_,_), C (_,_) -> true
    | _ -> false

let print_diffs ds =
  print_endline "{{{";
  List.iter (fun d -> print_endline (string_of_diff d)) ds;
  print_endline "}}}"

let print_additions d =
  match d with
    | ADD d -> print_endline ("\n+ " ^ string_of_gtree' d)
    | RM d -> print_endline ("\n- " ^ string_of_gtree' d)
    | UP(s,t) -> 
	(print_endline (string_of_diff d);
	 print_newline ())
    | ID d -> () (* print_endline ("\n= " ^ string_of_gtree' d)*)
    | _ -> ()

(*let apply_list gt1 ds = *)
(*let app_nonexec s d = try apply_noenv d s with omatch -> s in*)
(*List.fold_left app_nonexec s ds*)

let unabstracted_sol gt1 gt2 = 
  get_ctf_diffs_safe [] gt1 gt2
    (*print_endline "\n== get_ctf_diffs succeeded ==";*)
    (*List.iter print_additions dgts;*)
    (*print_endline "== those were the additions ==";*)
    (*print_endline "<< hierarchy >>";*)
    (*print_endline (string_of_subtree (make_subpatch_tree dgts gt1 gt2));*)
    (* get the list of those diffs that are complete *)
    (*let cgts = List.filter (fun d -> complete_patch gt1 gt2 [d]) dgts in*)
    (* take out those that are complete in them selves *)
    (*let dgts = List.filter (fun d -> not(List.mem d cgts)) dgts in*)
    (*print_endline "dgts::::::";*)
    (*List.iter (fun d -> print_endline (string_of_diff d)) dgts;*)
    (*print_newline ();*)
    (*if dgts = []*)
    (* there were only complete updates; thus we should simply return the smallest
     * one of those; there does not seem to be any good reason to return any
     * others
     *)
    (*then*)
    (*try [[List.hd cgts]] with (Failure "hd") -> []*)
    (*else*)
    (* since we now have to look at the smaller updates, we can rest assured
     * that if the constructed patches update the smallest of the complete one
     * correctly, they will also update the entire program correctly; this means
     * in turn that we look at smaller terms and can expect faster running time;
     * furthermore, and this is the important part, the collect function returns
     * the gt1,gt2 pair if a constructed patch was not complete and that would
     * imply that if NONE of the constructed patches were complete, which could
     * be caused by only having wrong/incomplete updates inferred, we would
     * return the entire gt1,gt2 pair as the result. In other words we ensure
     * gt1 and gt2 correspond to the smallest possible terms (which is safe as
     * said just before)
     *)
    (*let UP(gt1, gt2) = List.hd cgts in*)
    (*let parted = partition dgts in*)
    (*print_endline "parted::::::";*)
    (*List.iter print_diffs parted;*)
    (*let all_perms = gen_perms parted in*)
    (*print_endline "all_perms 1 :::::";*)
    (*List.iter print_diffs all_perms;*)
    (*print_newline ();*)
    (*let all_perms = List.map sort all_perms in*)
    (*print_endline "all_perms 2 :::::";*)
    (*List.iter print_diffs all_perms;*)
    (*print_newline ();*)
    (*let all_perms = List.map (fun d -> collect gt1 gt2 d) all_perms in*)
    (*print_endline "collected :::::";*)
    (*List.iter print_diffs all_perms;*)
    (*print_newline ();*)
    (*let all_perms = rm_dub all_perms in*)
    (*print_endline ">>>>>>>>>>>>> now we have:";*)
    (*print_sols all_perms;*)
    (*all_perms*)

let make_subterms_update up =
  match up with
    | UP(lhs, rhs) -> 
	(make_all_subterms lhs) % 
	  (make_all_subterms rhs)
    | RM t | ADD t | ID t -> make_all_subterms t

let make_subterms_patch ds =
  List.fold_left (fun subt_acc up ->
    make_subterms_update up % subt_acc) [] ds

(* takes an e list list and returns the e list with the property that all e's in
 * the returned list appear in all the input e lists
 *)

let inAll e ell = List.for_all (fun l -> List.mem e l) ell

let filter_all_old ell =
  List.fold_left (fun acc l -> List.fold_left (fun acc e ->
    if inAll e ell
    then e %% acc
    else acc
  ) acc l) [] ell

let filter_all ell =
  match ell with
    | sublist :: lists -> 
	List.filter (function e -> inAll e lists) sublist
    | [] -> []


let inSome e ell = 
  let occurs = List.length (List.filter (fun l -> List.mem e l) ell) in
    (*occurs >= List.length ell - !no_exceptions*)
    occurs >= !no_occurs

let filter_some ell =
  (* print_endline ("[Diff] no_occurs: " ^ string_of_int !no_occurs);  *)
  List.fold_left (fun acc l -> List.fold_left (fun acc e ->
    if inSome e ell
    then e %% acc
    else acc
  ) acc l) [] ell

(* takes a diff list (patch) and finds the subterms in the small updates;
 * we should take a flag to enable strict frequency or relaxed
 * with strict freq. an item, must be in all small updates in all patches
 * with relaxed an item, must appear somewhere in all patches (not necessarily
 * in all small updates as in the strict version
 *
 *)
let frequent_subterms_patch ds =
  debug_msg "Frequent subterms in patch";
  let tll = List.map make_subterms_update ds in
    debug_msg "filtering in patch";
    (*filter_all tll*)
    List.flatten tll

let frequent_subterms_patches ps =
  debug_msg "Frequent subterms in patches";
  let freq_subterms_lists = 
    List.map frequent_subterms_patch ps in
    debug_msg "filtering in patches";
    filter_all freq_subterms_lists

let frequent_subterms_changeset cs =
  debug_msg "Frequent subterms in changeset";
  let freq_subterms = 
    (*List.map frequent_subterms_patches cs in*)
    List.map frequent_subterms_patch cs in
    debug_msg "filtering in changeset";
    (* TODO: Use dmine instead of filter_all so that we can support an exception
     * level. The idea is that if we allow exceptions to the number of times a
     * term can appear, then we must somehow compensate for that when we look for
     * frequent items.
     *)
    filter_all freq_subterms


let make_fixed_list term_pairs =
  let subterms = List.map 
    (function (gtn, _) -> 
      fdebug_string !print_abs ("[Diff] making all subterms for :\n\t");
      fdebug_endline !print_abs (string_of_gtree' gtn);
      make_all_subterms gtn) term_pairs in
    (* Here we should allow frequent subterms that are not global; we could use
     * dmine to implement it, but I think it is so simple that we need only do a
     * simple filtering
     *)
    if !do_dmine
    then
      filter_some subterms
    else 
      filter_all subterms

let make_fixed_list_old updates =
  let subterms_list =
    List.fold_left (fun acc_list (gt1, gt2) ->
      ((make_all_subterms gt1) % (make_all_subterms gt2)) :: acc_list
    ) [] updates in
  let empty_db = DBM.makeEmpty () in
  let subterm_db = List.fold_left DBM.add_itemset empty_db subterms_list in
  let db_size = DBM.sizeOf subterm_db in
    (*print_string  "There are ";*)
    (*print_string  (string_of_int db_size);*)
    (*print_endline " itemsets";*)
    (*print_endline "With sizes:";*)
    DBM.fold_itemset subterm_db 
      (fun () is -> print_string ("[" ^ string_of_int
				     (List.length is) ^"]")) ();
    print_newline ();
    print_string "Finding frequent subterms...";
    flush stdout;
    let mdb = DBM.dmine subterm_db db_size in
    let cdb = mdb in (* DBM.close_db subterm_db mdb in *)
      print_endline "done.";
      (*DBM.print_db (string_of_gtree str_of_ctype str_of_catom) cdb;*)
      (*let itemset = DBM.fold_itemset cdb select_max [] in*)
      let itemset = DBM.fold_itemset cdb union_lists [] in
	print_endline "Frequent items selected:";
	List.iter (fun e -> 
	  print_endline 
	    (string_of_gtree str_of_ctype str_of_catom e)) 
	  itemset;
	list_fixed itemset

(*let jlist = [s;f;h;w]*)
(*let jfix  = list_fixed jlist*)


let read_src_tgt src tgt =
  let gt1 = gtree_of_ast_c (read_ast src) in
  let gt2 = gtree_of_ast_c (read_ast tgt) in
    gt1, gt2

let is_def gt = match view gt with
  | C("def", _) -> true
  | _ -> false

let extract_gt p gt = 
  let rec loop acc gt = 
    if p gt then gt :: acc 
    else match view gt with
      | A _ -> acc
      | C(_, ts) -> ts +> List.fold_left loop acc
  in loop [] gt

let get_fname_ast gt = match view gt with
  | C("def", gt_name :: _ ) -> (
      match view gt_name with 
	| A("fname", name) -> name
	| _ -> raise (Fail "no fname!")
    )
  | _ -> raise (Fail "no fname!!")

let read_src_tgt_def src tgt =
  let gts1 = gtree_of_ast_c (read_ast src)
    +> extract_gt is_def in
  let gts2 = gtree_of_ast_c (read_ast tgt)
    +> extract_gt is_def in
    gts1 +> List.rev_map 
      (function gt1 -> 
	 let f_name = get_fname_ast gt1 in
	   (gt1, 
	    gts2 +> List.find 
	     (function gt2 -> 
		get_fname_ast gt2 = f_name
	     )
	   )
      )


let verbose = ref false

let get_fun_name_gflow f =
  let head_node = f#nodes#tolist +> List.find (function (i,n) -> match view n with
    | C("head:def", [{node=C("def",_)}]) -> true
    | _ -> false) in
    match view (snd head_node) with
      | C("head:def",[{node=C("def",name::_)}]) -> (match view name with
          | A("fname",name_str) -> name_str
	  | _ -> raise (Fail "impossible match get_fun_name_gflow")
	)
      | _ -> raise (Fail "get_fun_name?")

(* depth first search *)
let dfs_iter xi' f g =
  let already = Hashtbl.create 101 in
  let rec aux_dfs xs = 
    xs +> List.iter (fun xi -> 
      if Hashtbl.mem already xi then ()
      else begin
        Hashtbl.add already xi true;
        if not(xi = xi')
        then f xi;
        let succ = g#successors xi in
          aux_dfs (succ#tolist +> List.map fst);
      end
    ) in
    aux_dfs [xi']

let seq_of_flow f = 
  let seq = ref [] in
  let start_idx = 0 in
  let add_node i = seq := f#nodes#find i :: !seq in
    dfs_iter start_idx add_node f;
    (* !seq +> List.filter (function (i, t) -> non_phony t) +> List.rev *)
    !seq +> List.rev


let dfs_diff f1 f2 = 
  let seq1 = seq_of_flow f1 in
  let seq2 = seq_of_flow f2 in
    (* get_diff_nonshared seq1 seq2 *)
    patience_diff seq1 seq2
    +> normalize_diff


let tl = List.tl
let hd = List.hd

let rec get_marked_seq ss = match ss with
  | ID t :: ADD t' :: ss' | ADD t' :: ID t :: ss' -> ID t +++ get_marked_seq (tl ss)
  | RM t :: ss -> RM t +++ get_marked_seq ss
  | _ :: ss -> get_marked_seq ss
  | [] -> []

let print_diff_flow di =
        di
    (*    +> get_marked_seq *)
        +> List.iter (function m -> 
                match m with
                (* | ID (i, t) -> print_endline ("@" ^ string_of_int i ^ "\t" ^ string_of_gtree' t)
                | ADD (i, t) -> print_endline ("@" ^ string_of_int i ^ "+\t" ^ string_of_gtree' t)
                | RM (i, t) -> print_endline ("@" ^ string_of_int i ^ "-\t" ^ string_of_gtree' t) *)
                | ID t -> print_endline ("\t" ^ string_of_gtree' t)
                | ADD t -> print_endline ("+\t" ^ string_of_gtree' t)
                | RM t -> print_endline ("-\t" ^ string_of_gtree' t)
                )

let flow_changes = ref []

let get_flow_changes flows1 flows2 =
    flows1 +> List.iter (function f ->
      let fname = get_fun_name_gflow f in
        try 
          let f' = flows2 +> List.find 
            (function f' -> get_fun_name_gflow f' = fname) in
            let diff = dfs_diff f f' in
            flow_changes := diff :: !flow_changes;
            if !verbose then print_diff_flow diff with Not_found -> ()
    )


let read_src_tgt_cfg src tgt =
  let (ast1, flows1) = read_ast_cfg src in
  let (ast2, flows2) = read_ast_cfg tgt in
    if !verbose then (
      print_endline "[Diff] gflows for file:";
      print_endline "[Diff] LHS flows";
      flows1 +> List.iter print_gflow;
      print_endline "[Diff] RHS flows";
      flows2 +> List.iter print_gflow;
      print_endline "[Diff] DFS diff");
    (* for each g1:fun<name> in flows1 such that g2:fun<name> in flows2:
     * we assume all g in flows? are of function-flows
     * compute diff_dfs g1 g2
     * print diff
     *)
    get_flow_changes flows1 flows2;
    (gtree_of_ast_c ast1, flows1),
  (gtree_of_ast_c ast2, flows2)

(* this function takes a list of patches (diff list list) and looks for the
 * smallest size of any update; the size of an update is determined by the gsize
 * of the left-hand-side 
 *)
let gsize_diff d =
  match d with
    | ID l | RM l | ADD l | UP (l,_) -> Some (gsize l)
let opt_min a b =
  match a, b with
    | None, c | c, None -> c
    | Some l, Some r -> Some (min l r)
let min_list size_f cur_min ls =
  List.fold_left (fun a_min el -> opt_min a_min (size_f el)) cur_min ls

let find_smallest_level ps_list =
  match List.fold_left (min_list gsize_diff) None ps_list with
    | None -> (print_endline "no minimal size!"; 0)
    | Some n -> n

(* we consider it beneficial that atoms that are common among all drivers which
 * also change should not be abstracted
 *)

let find_changed_terms_pair freq_fun (gt1, gt2) = 
  let c_parts = get_ctf_diffs_all [] gt1 gt2 in
  let rec loop c_parts =
    match c_parts with
      | [] -> []
      | UP(t, t') :: parts -> 
	  (*print_string ("[Diff: considering atom: " ^ string_of_gtree' t);*)
	  if freq_fun t
	  then (
            (*print_endline " changed AND common";*)
            t :: loop parts)
	  else (
            (*print_newline ();*)
            loop parts)
      | _ :: parts -> loop parts in
    loop c_parts

let find_changed_terms freq_fun term_pairs =
  let changed_t_lists = List.map (find_changed_terms_pair freq_fun) term_pairs in
    filter_all changed_t_lists


let filter_safe (gt1, gt2) parts =
  List.filter (function bp -> 
		 safe_part bp (gt1, gt2)
    (* if safe_part bp (gt1, gt2) *)
    (* then true *)
    (* else ( *)
    (*   print_string "[Diff] unsafe part:\n\t"; *)
    (*   print_endline (string_of_diff bp); *)
    (*   false *)
    (* ) *)
  ) parts

    

(* two patches commute with respect to a changeset if the order in
   which they are applied does not matter (and the combined version is a
   safe part)
*)
let commutes chgset bp bp' =
  let bp1 = SEQ(bp,bp') in
  let bp2 = SEQ(bp',bp) in
    eq_changeset chgset bp1 bp2

let make_abs terms_changed fixf (gt1, gt2) =
  (* first make the list of concrete safe parts *)
  
  let c_parts = 
    if !malign_mode
    then (
      print_string "[Diff] getting concrete parts ...";
      let cs = get_tree_changes gt1 gt2 in
	print_endline (cs +> List.length +> string_of_int ^ " found");
	print_endline ("[Diff] filtering " ^ 
			 cs +> List.length +> string_of_int ^ " safe parts");
	(*List.iter (function d -> print_endline (string_of_diff d)) cs;*)
	List.filter (function up -> 
		       print_endline "[Diff] filtering cpart:";
		       up +> string_of_diff +> print_endline;
		       safe_part up (gt1, gt2)
		    ) cs
    ) else get_ctf_diffs_safe [] gt1 gt2 
  in
    print_endline ("[Diff] number of concrete parts: " ^ string_of_int (List.length c_parts));
    (* new generalize each such part and add it to our resulting list in case it
     * is not already there and in case it is still a safe part
     *)
    print_endline "[Diff] finding abstract parts";
    let a_parts = List.flatten (
      List.map (function c_up ->
		  let cand_abs = abs_term_noenv 
		    terms_changed fixf
		    should_abs_depth c_up in
		    (filter_safe (gt1, gt2) cand_abs)
	       )
  	c_parts) in
      a_parts

let sub_term env t =
  if env = [] then t else
    let rec loop t' = 
      try List.assoc t' env with Not_found ->
	(match view t' with
	   | C(ty,ts) -> mkC(ty, ts
			       +> List.fold_left 
			       (fun acc_ts t ->
				  loop t :: acc_ts
			       ) [] 
			       +> List.rev)
	   | _ -> t'
	) in
      loop t


let make_abs_on_demand term_pairs subterms_lists unique_subterms (gt1, gt2) =
  let c_parts = 
    if !malign_mode
    then (
      print_string "[Diff] getting concrete parts ...";
      let cs = get_tree_changes gt1 gt2 in
	print_endline (cs +> List.length +> string_of_int ^ " found");
	print_endline ("[Diff] filtering " ^ 
			 cs +> List.length +> string_of_int ^ " safe parts");
	List.filter (function up -> 
		       v_print_endline "[Diff] filtering cpart:";
		       up +> string_of_diff +> v_print_endline;
		       safe_part up (gt1, gt2)
		    ) cs
    ) else get_ctf_diffs_safe [] gt1 gt2 
  in
    print_endline ("[Diff] number of concrete parts: " ^ string_of_int (List.length c_parts));
    (* new generalize each such part and add it to our resulting list in case it
     * is not already there and in case it is still a safe part
     *)
    print_endline "[Diff] finding abstract parts using \"on-demand\" method";
    let rec abs_term_one env t t' =
      (* 
	 env : term * term list -- maps term from first term to metavariables in new term
	 t   : term
	 t'  : term   -- terms from which to produce abstraction
      *)
      if t = t' 
      then t, env 
      else match view t, view t' with
	| C(ty1, ts1), C(ty2, ts2) when 
 	    ty1 = ty2 && List.length ts1 = List.length ts2 -> 
 	    let ts', env' = List.fold_left2 
 	      (fun (acc_ts, env) t1 t2 -> 
  		 let t1', env' = abs_term_one env t1 t2 in
		   (t1' :: acc_ts, env')
  	      ) ([], env) ts1 ts2 in
	      mkC(ty1, List.rev ts'), env'
	| _, _ -> try List.assoc t env, env with Not_found -> 
	    let new_m = mkM () in
	      (* a limitation here is that we assume equal subterms to
		 always be abstracted by equal metavariables
	      *)
	      new_m, (t, new_m) :: env
    in		
    let rm_dup_env ls = 
      List.fold_left
	(fun acc (p,env) -> 
	   if List.exists (function (p',_) -> p' = p) acc 
	   then acc 
	   else (p, env) :: acc)
	[] ls
    in
    let abs_term_list t ts =
      let res = ts
	+> List.rev_map (function t' ->  reset_meta (); abs_term_one [] t t' +> fst) 
	+> List.filter (function t -> not(is_meta t))
	+> rm_dub in
	(* print_string ("abs_term_list " ^ string_of_gtree' t); *)
	(* print_endline (" on ts.length = " ^ ts +> List.length +> string_of_int); *)
	(* res +> List.iter (function (t,_) -> t +> string_of_gtree' +> print_endline); *)
	res
    in
    let abs_term_lists t ts_lists =
      ts_lists
      +> List.rev_map (abs_term_list t)
    in
    let get_patterns term =
      let add_abs t =
	(* print_endline "[Diff] adding pattern:"; *)
	(* t +> string_of_gtree' +> print_endline;  *)
	try 
	  let cnt = Hashtbl.find count_ht t in
	    Hashtbl.replace count_ht t (cnt + 1)
	with Not_found ->
	  Hashtbl.replace count_ht t 1 in
      let rec count term =
	abs_term_lists term subterms_lists
	+> List.iter 
	  (function abs_list ->
	     abs_list 
	     +> List.iter add_abs
	  )
      in
	begin
	  if !not_counted
	  then begin
	    print_string "[Diff] initial term abstraction...";
	       let n = ref 0 in
	       let m = List.length unique_subterms in
		 unique_subterms +> List.iter (function uniq_t -> begin
						 if !n mod 100 = 0
						 then begin
						   ANSITerminal.save_cursor ();
						   ANSITerminal.print_string 
						     [ANSITerminal.on_default](
						       !n +> string_of_int ^"/"^
							 m +> string_of_int);
						   ANSITerminal.restore_cursor();
						   flush stdout;
						 end;
						 n := !n + 1;
						 count uniq_t
					       end);
		 not_counted := false;
	  end;
	  Hashtbl.fold 
	    (fun pattern occurs acc ->
	       (* print_endline ("[Diff] pattern occurrences: " ^ occurs +> string_of_int); *)
	       (* pattern +> string_of_gtree' +> print_endline; *)
	       if occurs >= !no_occurs 
	       then
		 try
		   let env = match_term pattern term in
		     (pattern, env) :: acc
		 with Nomatch -> acc
	       else (
		 (* print_endline ("Infrequent pattern ("^occurs +> string_of_int^"):"); *)
		 (* pattern +> string_of_gtree' +> print_endline;  *)
		 acc)
	    ) count_ht []
	end
    in
      c_parts 
      +> List.fold_left
	(fun acc_parts c_up ->
	   match c_up with
	     | UP(lhs,rhs) -> 
		 v_print_endline ("[Diff] get patterns for:" ^ 
				    lhs +> string_of_gtree');
		 let p_env = get_patterns lhs in
		   if !print_abs
		   then (
		     print_endline ("[Diff] for UP(" ^
		   		      lhs +> string_of_gtree' ^ ", " ^
		   		      rhs +> string_of_gtree'
		   		    ^ ") we found the following patterns:");
		     p_env +> List.iter
		       (function (p,_) -> p +> string_of_gtree' +> print_endline);
		   );
		   p_env +> List.fold_left 
		     (fun acc_parts (p,env) -> 
			let p' = rev_sub env rhs in
			let up = UP(p,p') in
			  if safe_part up (gt1, gt2)
			  then (
			    if !print_abs
			    then (
			      print_endline "[Diff] found *safe* part:";
			      up +> string_of_diff +> print_endline; 
			    );
			    up +++ acc_parts
			  )
			  else (
			    if !print_abs 
			    then (
			      print_endline "[Diff] *UNsafe* part:";
			      up +> string_of_diff +> print_endline; 
			    );
			    acc_parts
			  )
		     ) acc_parts
	     | _ -> raise (Fail "non supported update ...")
	) []
	

(* This function returns a boolean value according to whether it can
 * syntactically* determine two atomic patches to have disjoint
 * domains.  The domains are disjoint if neither p1 is embedded in p2
 * nor vice versa. One caveat is that since patterns contains
 * metavariables, we can not simply use a simple syntactic criterion
 * for deciding whether a pattern is embedded in anther. For this
 * reason, we (mis)use the "apply" function instead.
 *)

let disjoint_domains (bp1, bp2) =
  match bp1, bp2 with
    | UP(p1,_), UP(p2,_) ->
        let a1 = try 
            apply_noenv bp1 p2; false with Nomatch -> true
        and a2 = try 
            apply_noenv bp2 p1; false with Nomatch -> true
        in
          a1 && a2


let print_sol_lists sol_lists =
  List.iter 
    (fun sl -> 
      print_endline "<<<<<<< sol list >>>>>>>";
      if sl = []
      then
	print_endline "[]"
      else
	print_sols sl
    ) sol_lists



(* The merge_patterns function tries to merge two patterns into one which match
 * both of the patterns, but which abstracts only those subterms which NEED to
 * be abstracted
 *)
let rec merge_patterns p1 p2 =
  let rec loop p1 p2 =
    match view p1, view p2 with
      | _, _ when p1 == p2 -> p1
      | _, A("meta", v2) -> p2
      | A("meta",_), _ -> p1
      | C(t1,ts1), C(t2,ts2) when 
            t1 = t2 && List.length ts1 = List.length ts2 -> 
          mkC (t1, List.fold_left2 (fun acc_ts t1 t2 ->
            loop t1 t2 :: acc_ts
          ) [] ts1 ts2)
      | _, _ -> let m = "X" ^ string_of_int (ref_meta()) in
		  make_gmeta m
  in
    match view p1, view p2 with
      | _, _ when p1 == p2 -> Some p1
      | C(t1,ts1), C(t2,ts2) when
            t1 = t2 && List.length ts1 = List.length ts2 -> 
          Some (loop p1 p2)
      | _, _ -> None


(* based on the assumption that in a diff, we always block removals/additions
 * the following function splits a diff into chunks each being of the form:
         * chunk ::= (+p)* (-p | p) (+p)*
 * that is: each chunk contains a context node (the -p,p) and some additions.
 * One should take note that given a diff, there can be more than one way to
 * split it according to the chunk-def given. However, any partitioning will be
 * just fine for us.
 *)

let chunks_of_diff diff =
        let rec loop acc_chunks chunk diff = match diff with
        | [] -> List.rev ((List.rev chunk) :: acc_chunks)
        | i :: diff' -> (match i with
          | ADD t -> loop acc_chunks (i :: chunk) diff'
          | ID t | RM t -> _loop acc_chunks (i :: chunk) diff'
        ) 
        and _loop acc_chunks chunk diff = match diff with
        | [] -> loop acc_chunks chunk []
        | i :: diff' -> (match i with
          | ADD _ -> _loop acc_chunks (i :: chunk) diff'
          | _ -> loop ((List.rev chunk) :: acc_chunks) [] diff
        ) in
        loop [] [] diff




