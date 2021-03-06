module Ast0 = Ast0_cocci
module Ast = Ast_cocci

(* types that clutter the .mly file *)
(* for iso metavariables, true if they can only match nonmodified, unitary
   metavariables *)
type fresh = bool

type clt =
    line_type * int * int * int * int (* starting spaces *) *
      (string * Ast0.position_info) list (* code before *) *
      (string * Ast0.position_info) list (* code after *) *
      Ast0.meta_pos (* position variable, minus only *)

(* ---------------------------------------------------------------------- *)

(* Things that need to be seen by the lexer and parser. *)

and line_type =
    MINUS | OPTMINUS | UNIQUEMINUS
  | PLUS
  | CONTEXT | UNIQUE | OPT

type iconstraints = Ast0.ident list
type econstraints = Ast0.expression list
type pconstraints = Ast.meta_name list

let in_rule_name = ref false
let in_meta = ref false
let in_iso = ref false
let in_generating = ref false
let in_prolog = ref false
let inheritable_positions =
  ref ([] : string list) (* rules from which posns can be inherited *)

let all_metadecls =
  (Hashtbl.create(100) : (string, Ast.metavar list) Hashtbl.t)

let clear_meta: (unit -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_id_meta:
    (Ast.meta_name -> iconstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_type_meta: (Ast.meta_name -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_init_meta: (Ast.meta_name -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_param_meta: (Ast.meta_name -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_paramlist_meta:
    (Ast.meta_name -> Ast.meta_name option -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_const_meta:
    (Type_cocci.typeC list option -> Ast.meta_name -> econstraints ->
      Ast0.pure -> unit)
    ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_err_meta:
    (Ast.meta_name -> econstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_exp_meta:
    (Type_cocci.typeC list option -> Ast.meta_name -> econstraints ->
      Ast0.pure -> unit)
    ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_idexp_meta:
    (Type_cocci.typeC list option -> Ast.meta_name -> econstraints ->
      Ast0.pure -> unit)
    ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_local_idexp_meta:
    (Type_cocci.typeC list option -> Ast.meta_name -> econstraints ->
      Ast0.pure -> unit)
    ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_explist_meta:
    (Ast.meta_name -> Ast.meta_name option -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_stm_meta: (Ast.meta_name -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_stmlist_meta: (Ast.meta_name -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_func_meta:
    (Ast.meta_name -> iconstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_local_func_meta:
    (Ast.meta_name -> iconstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_declarer_meta:
    (Ast.meta_name -> iconstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_decl")

let add_iterator_meta:
    (Ast.meta_name -> iconstraints -> Ast0.pure -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_iter")

let add_pos_meta:
    (Ast.meta_name -> pconstraints -> Ast.meta_collect -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_meta")

let add_type_name: (string -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_type")

let add_declarer_name: (string -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_decl")

let add_iterator_name: (string -> unit) ref =
  ref (fun _ -> failwith "uninitialized add_iter")

let init_rule: (unit -> unit) ref =
  ref (fun _ -> failwith "uninitialized install_bindings")

let install_bindings: (string -> unit) ref =
  ref (fun _ -> failwith "uninitialized install_bindings")
