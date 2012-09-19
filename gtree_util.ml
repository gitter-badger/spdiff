open Gtree
open Env

let metactx = ref 0
let reset_meta () = metactx := 0
let inc x = let v = !x in (x := v + 1; v)
let ref_meta () = inc metactx
let mkM () = mkA("meta", "X" ^ string_of_int(ref_meta()))
let meta_name m = match view m with
  | A("meta", n) -> n
  | _ -> raise (failwith "trying to fetch metaname of non-meta value")

let make_gmeta name = mkA ("meta", name)

let new_meta env t =
  let m = "X" ^ string_of_int (ref_meta ()) in
    [make_gmeta m], [(m,t)]
let is_meta v = match view v with | A("meta", _) -> true | _ -> false

let merge_terms t1 t2 =
  let rec loop env t1 t2 = 
    if t1 == t2 
    then (t1, env)
    else match view t1, view t2 with
      | C(ty1, ts1), C(ty2, ts2) 
        when ty1 = ty2 && List.length ts1 = List.length ts2
	      -> let ts1, env' = List.fold_left2 
	            (fun (acc_ts, env') t1' t2' -> 
	                let t'', env'' = loop env' t1' t2'
	                in (t'' :: acc_ts, env'')
	            ) 
              ([],env) ts1 ts2
	         in (mkC(ty1, List.rev ts1), env')
      | _ -> 
          (match rev_lookup env (t1, t2) with
		        | None -> let meta = mkM () in
                      let metaName = meta_name meta in
		                  (meta, (metaName, (t1,t2)) :: env)
		        | Some name -> (mkA ("meta", name), env)
	        )					
  in
    loop [] t1 t2

