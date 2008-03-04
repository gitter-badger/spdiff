(* collect information *)

let function_table =
  (Hashtbl.create(100) :
     (string(*fn*),
      (string(*fl*) *
	 (bool (* true if static *) * string list (* callees *) *
	    (string (*fl*) * string (*fn*)) list ref (*indirect callees*)))
	list ref)
     Hashtbl.t)

let file_table =
  (Hashtbl.create(100) :
     (string(*file*),(string list (*includes*) * string list(*fns*)))
     Hashtbl.t)

let rec union_list = function
    [] -> []
  | x::xs -> Common.union_set x (union_list xs)

(* find what each function calls.  find what is defined in each file. *)
let collect_info home file =
  let (parsed,_) = Parse_c.parse_print_error_heuristic file in
  let file =
    let start =
      let len = String.length home in
      if String.get home (len - 1) = '/'
      then len
      else len + 1 in
    String.sub file start (String.length file - start) in

  let locals = ref [file] in

  let current_function = ref "" in
  let current_function_static = ref false in

  let functions = ref [] in
  let calls = ref [] in

  let add_name calls =
    if not (!current_function = "")
    then
      let cell =
	try Hashtbl.find function_table !current_function
	with Not_found ->
	  let cell = ref [] in
	  Hashtbl.add function_table !current_function cell;
	  cell in
      (* problem: a function can be define more than once in a file, because
	 of ifdefs *)
      let rec loop = function
	  [] -> [(file,(!current_function_static,calls,ref []))]
	| ((f1,(a,b,c)) as cur)::rest ->
	    if file = f1
	    then
	      let is_static =
		if not (!current_function_static = a)
		then
		  (Printf.printf "incoherent storage for %s, assuming extern\n"
		    !current_function;
		   false)
		else a in
	      (file,(is_static,Common.union_set calls b,c)) :: rest
	    else cur::(loop rest) in
      cell := loop !cell in
  
  let bigf =
    { Visitor_c.default_visitor_c with 

      Visitor_c.kprogram = (function (k,bigf) -> function
	  Ast_c.Include(fl,_) ->
	    (match Ast_c.unwrap fl with
	      Ast_c.Local path ->
		(*
		Printf.printf "adding for %s : %s\n" file
		  ((Filename.dirname file) ^ "/" ^ (String.concat "/" path));
		   *)
		locals :=
		  ((Filename.dirname file) ^ "/" ^ (String.concat "/" path))
		  :: !locals
	    | _ -> ())
	| prog -> k prog);
      
      Visitor_c.kdef = (fun (k,bigf) def -> 
	let (name,ty,(sto,_),body) = Ast_c.unwrap def in
	add_name !calls;
	current_function := name;
	current_function_static :=
	  (match sto with
	    Ast_c.Sto(Ast_c.Static) -> true
	  | _ -> false);
	calls := [];
	functions := name :: !functions;
	k def);
      
      Visitor_c.kexpr = (fun (k,bigf) expr -> 
	k expr; (* recurse on the sub expressions *)
	match Ast_c.unwrap_expr expr with
	  Ast_c.FunCall (((Ast_c.Ident f, typ), ii), args) ->
	    calls := Common.union_set [f] !calls
	| _ -> ()) } in
  
  List.iter (function (x,_) -> Visitor_c.vk_program bigf x) parsed;
  (* the last function read in *)
  add_name !calls;
  Hashtbl.add file_table file (!locals,!functions);
  (file,!functions)

(* ---------------------------------------------------------------------- *)
(* initialize all_callees *)

let find_extern l =
  List.filter (function (_,(false,_,_)) -> true | _ -> false) l

let multi_assoc locals info =
  let rec loop = function
      [] -> raise Not_found
    | (x,info)::xs when List.mem x locals -> (x,info)
    | _::xs -> loop xs in
  loop info
    
let find_callee locals callee good bad =
  try
    match !(Hashtbl.find function_table callee) with
      [x] -> Some (good x)
    | l ->
	try
	  let defining_file_definition = multi_assoc locals l in
	  Some (good defining_file_definition)
	with Not_found ->
	  match find_extern l with
	    [x] -> Some (good x)
	  | l ->
	      Printf.printf "%d things found for %s:\n   %s\n"
		(List.length l) callee
		(String.concat " " (List.map (function (fl,_) -> fl) l));
	      None
  with Not_found -> Some (bad())

let init_all_callees _ =
  Hashtbl.iter
    (function fn ->
      function l ->
	List.iter
	  (function (defining_file,(is_static,callees,all_callees)) ->
	    let (locals,_) = Hashtbl.find file_table defining_file in
	    all_callees :=
	      List.concat
		((List.map
		   (function callee ->
		     let good (fl,(_,_,_)) = [fl] in
		     let bad _ = [] in
		     match find_callee locals callee good bad with
		       Some fls -> List.map (function fl -> (fl,callee)) fls
		     | None ->
			 Printf.printf
			   "cannot find a unique file for function %s\n"
			   callee;
			 Printf.printf "   tried among\n   %s\n"
			   (String.concat ", " locals);
			 [])
		   callees) : (string * string) list list))
	  !l)
    function_table

(* ---------------------------------------------------------------------- *)
(* process information *)

let changed = ref false

let rec process_one fl fn =
  try
    let (_,_,all_callees) =
      (* find the information about this function in what is known to be
	 its file *)
      List.assoc fl !(Hashtbl.find function_table fn) in
    let old = !all_callees in
    let upd =
      Common.union_set old
	(union_list
	   (List.map
	      (function (fl,callee) ->
		let (_,_,all_callees) =
		  (* find the information about the callee, in what is known
		     to be its file *)
		  List.assoc fl !(Hashtbl.find function_table callee) in
		!all_callees)
	      old)) in
    if not(List.length old = List.length upd)
    then
      begin
	changed := true;
	all_callees := upd
      end
  with Not_found -> ()

let rec iter file_functions =
  changed := false;
  List.iter
    (function (file,functions) ->
      List.iter (process_one file) functions)
    file_functions;
  if !changed then iter file_functions
	
(* ---------------------------------------------------------------------- *)
(* print result *)

(* For each file, collect all of the callees.  Then find the file for each
callees.  Then count the number of files that are represented. *)
	
let collect_per_file file functions =
  let all_callees =
    union_list
      (List.map
	 (function fn ->
	   let (_,callees,all_callees) =
	     List.assoc file !(Hashtbl.find function_table fn) in
	   !all_callees)
	 functions) in
  let info =
    List.sort compare
      (List.map (function (defining_file,fn) -> defining_file) all_callees) in
  let rec loop = function
      [] -> []
    | f::fs ->
	match loop fs with
	  [] -> [(f,1)]
	| (f1,ct)::rest when f=f1 -> (f1,ct+1)::rest
	| rest -> (f,1)::rest in
  loop info
    
let print_res file functions (* functions in the file *) =
  match collect_per_file file functions with
    [] -> ()
  | info ->
      Printf.printf "%s:\n" file;
      List.iter
	(function (file,count) ->
	  let (_,functions) = Hashtbl.find file_table file in
	  let sz = List.length functions in
	  Printf.printf "  %s: %d out of %d = %d percent\n"
	    file count sz ((100 * count) / sz))
	info
    
(* ---------------------------------------------------------------------- *)
(* entry point *)

    
let _ =
  let dirs = ref ([] : string list) in
  let target = ref "" in
  let options =
    ["-target",  Arg.Set_string target, " <file> the file to focus on"] in
  Arg.parse (Arg.align options) (fun x -> dirs := x::!dirs) "";
  Flag_parsing_c.verbose_parsing := false;
  Flag_parsing_c.verbose_type := false;

  let files =
    Common.cmd_to_list ("find " ^(Common.join " " !dirs) ^" -name \"*.c\"") in
  let files = files @
    Common.cmd_to_list ("find " ^(Common.join " " !dirs) ^" -name \"*.h\"") in
  let head = match !dirs with [x] -> x | _ -> "" in
  let file_functions = List.map (collect_info head) files in
  init_all_callees();
  if not (!target = "")
  then
    let mini_file_functions =
      List.filter
	(function (file,functions) ->
	  try
	    let _ = Str.search_forward (Str.regexp !target) file 0 in
	    true
	  with Not_found -> false)
	file_functions in
    match mini_file_functions with
      [] -> failwith "target file not found"
    | _ -> iter mini_file_functions
  else iter file_functions;
  List.iter (function (file,functions) -> print_res file functions)
    file_functions
