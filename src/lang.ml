open Core.Std
open Printf
open Util
open Fn

(**** Language {{{ *****)

exception Internal_error of string
let internal_error f s = raise @@ Internal_error (sprintf "(%s) %s" f s)

type regex =
  | RegExBase of string
  | RegExConcat of regex * regex
  | RegExOr of regex * regex
  | RegExStar of regex
  | RegExUserDefined of string

type examples = (string * string) list

type specification = (string * regex * regex * (string * string) list)

type synth_problems = (string * regex) list * (specification list) 

type synth_problem = (((string * regex) list) * string * regex * regex * (string * string) list)

type unioned_subex = concated_subex list

and concated_subex = basis_subex list

and basis_subex =
  | NRXBase of string
  | NRXStar of unioned_subex
  | NRXUserDefined of string

type normalized_regex = unioned_subex

type normalized_synth_problem = ((string * normalized_regex) list)
                                * normalized_regex * normalized_regex
                                * (string * string) list

type context = (string * regex) list

let problems_to_problem_list ((c,ss):synth_problems) : synth_problem list =
  List.map ~f:(fun (n,r1,r2,exl) -> (c,n,r1,r2,exl)) ss

let rec to_normalized_exp (r:regex) : normalized_regex =
  begin match r with
  | RegExBase c -> [[NRXBase c]]
  | RegExConcat (r1,r2) ->
      cartesian_map (@) (to_normalized_exp r1) (to_normalized_exp r2)
  | RegExOr (r1,r2) -> (to_normalized_exp r1) @ (to_normalized_exp r2)
  | RegExStar (r') -> [[NRXStar (to_normalized_exp r')]]
  | RegExUserDefined s -> [[NRXUserDefined s]]
  end

let rec to_normalized_synth_problem ((c,n,r1,r2,es):synth_problem)
: normalized_synth_problem =
  (List.map ~f:(fun (s,r) -> (s, to_normalized_exp r)) c, to_normalized_exp r1, to_normalized_exp r2, es)



type atom =
  | AUserDefined of string
  | AStar of dnf_regex

and clause = atom list * string list

and dnf_regex = clause list

let empty_dnf_string : dnf_regex = [([],[""])]

let rec concat_dnf_regexs (r1:dnf_regex) (r2:dnf_regex) : dnf_regex =
  cartesian_map
    (fun (a1s,s1s) (a2s,s2s) -> (a1s@a2s,weld_lists (^) s1s s2s))
    r1
    r2

let rec or_dnf_regexs (r1:dnf_regex) (r2:dnf_regex) : dnf_regex =
  r1 @ r2

let rec concat_clause_dnf_rx (cl:clause) (r:dnf_regex) : dnf_regex =
  concat_dnf_regexs [cl] r

let rec concat_dnf_rx_clause (r:dnf_regex) (cl:clause) : dnf_regex =
  concat_dnf_regexs r [cl]

let rec exponentiate_dnf (r:dnf_regex) (n:int) : dnf_regex =
  if n < 0 then
    failwith "invalid exponential"
  else if n = 0 then
    empty_dnf_string
  else
    concat_dnf_regexs (exponentiate_dnf r (n-1)) r

let rec quotiented_star_dnf (r:dnf_regex) (n:int) : dnf_regex =
  if n < 1 then
    failwith "invalid modulation"
  else if n = 1 then
    empty_dnf_string
  else
    or_dnf_regexs (quotiented_star_dnf r (n-1)) (exponentiate_dnf r (n-1))

let rec singleton_atom (a:atom) : dnf_regex =
  [([a],["";""])]

let rec to_dnf_regex (r:regex) : dnf_regex =
  let rec atom_to_dnf_regex (a:atom) : dnf_regex =
    [([a],["";""])]
  in
  begin match r with
  | RegExBase c -> [([],[c])]
  | RegExConcat (r1,r2) ->
      cartesian_map
        (fun (a1s,s1s) (a2s,s2s) -> (a1s@a2s,weld_lists (^) s1s s2s))
        (to_dnf_regex r1)
        (to_dnf_regex r2)
  | RegExOr (r1, r2) -> (to_dnf_regex r1) @ (to_dnf_regex r2)
  | RegExStar (r') -> atom_to_dnf_regex (AStar (to_dnf_regex r'))
  | RegExUserDefined s -> atom_to_dnf_regex (AUserDefined s)
  end


let rec compare_atoms (a1:atom) (a2:atom) : comparison =
  begin match (a1,a2) with
  | (AUserDefined s1, AUserDefined s2) -> int_to_comparison (compare s1 s2)
  | (AUserDefined  _, AStar         _) -> LT
  | (AStar         _, AUserDefined  _) -> GT
  | (AStar        r1, AStar        r2) -> compare_dnf_regexs r1 r2
  end

and compare_clauses ((atoms1,strings1):clause) ((atoms2,strings2):clause) : comparison =
  ordered_partition_order compare_atoms atoms1 atoms2

and compare_dnf_regexs (r1:dnf_regex) (r2:dnf_regex) : comparison =
  ordered_partition_order compare_clauses r1 r2

type exampled_atom =
  | EAUserDefined of string * string list
  | EAStar of exampled_dnf_regex

and exampled_clause = (exampled_atom) list * string list * (int list list)

and exampled_dnf_regex = exampled_clause list

type exampled_regex =
  | ERegExBase of string * (int list list)
  | ERegExConcat of exampled_regex * exampled_regex * (int list list)
  | ERegExOr of exampled_regex  * exampled_regex * (int list list)
  | ERegExStar of exampled_regex * (int list list)
  | ERegExUserDefined of string * string list * (int list list)

let rec extract_example_list (er:exampled_regex) : int list list =
  begin match er with
  | ERegExBase (_,il) -> il
  | ERegExConcat (_,_,il) -> il
  | ERegExOr (_,_,il) -> il
  | ERegExStar (_,il) -> il
  | ERegExUserDefined (_,_,il) -> il
  end

type ordered_exampled_atom =
  | OEAUserDefined of string * string list
  | OEAStar of ordered_exampled_dnf_regex

and ordered_exampled_clause = ((ordered_exampled_atom * int) list) list * string
list * (int list list)

and ordered_exampled_dnf_regex = (ordered_exampled_clause * int) list list

let rec compare_exampled_atoms (a1:exampled_atom) (a2:exampled_atom) :
  comparison =
    begin match (a1,a2) with
    | (EAUserDefined (s1,el1), EAUserDefined (s2,el2)) ->
        begin match (int_to_comparison (compare s1 s2)) with
        | EQ -> ordered_partition_order
                  (fun x y -> int_to_comparison (compare x y))
                  el1
                  el2
        | x -> x
        end
    | (EAStar r1, EAStar r2) -> compare_exampled_dnf_regexs r1 r2
    | _ -> EQ
    end 

and compare_exampled_clauses ((atoms1,strings1,ints1):exampled_clause)
                             ((atoms2,strings2,ints2):exampled_clause)
                        : comparison =
  begin match ordered_partition_order compare_exampled_atoms atoms1 atoms2 with
  | EQ -> ordered_partition_order
            (fun x y -> int_to_comparison (compare x y))
            ints1
            ints2
  | c -> c
  end

and compare_exampled_dnf_regexs (r1:exampled_dnf_regex) (r2:exampled_dnf_regex) : comparison =
  ordered_partition_order
    compare_exampled_clauses
      r1
      r2

let rec compare_ordered_exampled_atoms (a1:ordered_exampled_atom)
                                       (a2:ordered_exampled_atom)
                                     : comparison =
    begin match (a1,a2) with
    | (OEAUserDefined (s1,el1), OEAUserDefined (s2,el2)) ->
        begin match (int_to_comparison (compare s1 s2)) with
        | EQ -> dictionary_order
                  (int_comparer_to_comparer compare)
                  el1
                  el2
        | x -> x
        end
    | (OEAStar r1, OEAStar r2) -> compare_ordered_exampled_dnf_regexs r1 r2
    | (OEAStar _, OEAUserDefined _) -> GT
    | (OEAUserDefined _, OEAStar _) -> LT
    end 

and compare_ordered_exampled_clauses
        ((atoms_partitions1,strings1,ints1):ordered_exampled_clause)
        ((atoms_partitions2,strings2,ints2):ordered_exampled_clause)
      : comparison =
  begin match ordered_partition_dictionary_order
                compare_ordered_exampled_atoms
                atoms_partitions1
                atoms_partitions2 with
  | EQ -> dictionary_order
            (fun x y -> int_to_comparison (compare x y))
            ints1
            ints2
  | c -> c
  end

and compare_ordered_exampled_dnf_regexs (r1:ordered_exampled_dnf_regex)
  (r2:ordered_exampled_dnf_regex) : comparison =
    ordered_partition_dictionary_order
      compare_ordered_exampled_clauses
        r1
        r2

let rec to_ordered_exampled_atom (a:exampled_atom) : ordered_exampled_atom =
  begin match a with
  | EAUserDefined (s,el) -> OEAUserDefined (s,el)
  | EAStar r -> OEAStar (to_ordered_exampled_dnf_regex r)
  end

and to_ordered_exampled_clause ((atoms,strings,exnums):exampled_clause) : ordered_exampled_clause =
  let ordered_atoms = List.map ~f:to_ordered_exampled_atom atoms in
  let ordered_ordered_atoms =
    sort_and_partition_with_indices
      compare_ordered_exampled_atoms
      ordered_atoms in
  (ordered_ordered_atoms,strings,exnums)

and to_ordered_exampled_dnf_regex (r:exampled_dnf_regex)
        : ordered_exampled_dnf_regex =
  let ordered_clauses = List.map ~f:to_ordered_exampled_clause r in
  sort_and_partition_with_indices
    compare_ordered_exampled_clauses
    ordered_clauses

let rec size (r:regex) : int =
  begin match r with
  | RegExBase _ -> 1
  | RegExConcat (r1,r2) -> (size r1) * (size r2)
  | RegExOr (r1,r2) -> (size r1) + (size r2)
  | RegExStar r' -> size r'
  | RegExUserDefined _ -> 1
  end


(***** }}} *****)
