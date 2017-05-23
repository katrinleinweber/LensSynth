open Core.Std
open Counters
open Regexcontext
open Language_equivalences
open Lenscontext
open Lang
open Util
open Permutation
open Normalized_lang
open Consts
open String_utilities

let rec true_max_size (c:RegexContext.t) (r:regex) : int =
  begin match r with
  | RegExEmpty -> 0
  | RegExBase _ -> 1
  | RegExConcat (r1,r2) -> (true_max_size c r1) * (true_max_size c r2)
  | RegExOr (r1,r2) -> (true_max_size c r1) + (true_max_size c r2)
  | RegExStar r' -> true_max_size c r'
  | RegExVariable t ->
      begin match RegexContext.lookup_for_expansion_exn c t with
      | None -> 1
      | Some r' -> true_max_size c r'
      end
  end


type synth_problem = (RegexContext.t * string * regex * regex * (string * string) list)

let problems_to_problem_list ((ds,ss):synth_problems) : synth_problem list =
  let rc = RegexContext.create_from_list_exn ds in
  List.map ~f:(fun (n,r1,r2,exl) -> (rc,n,r1,r2,exl)) ss



let get_rep_userdef
    (lc:LensContext.t)
    (ud:string)
  : string =
  if !use_lens_context then
    (fst (LensContext.shortest_path_to_rep_elt lc ud))
  else
    ud

let empty_string = RegExBase ""

let rec exponentiate (r:regex) (n:int) : regex =
  if n < 0 then
    failwith "invalid exponential"
  else if n = 0 then
    empty_string
  else
    RegExConcat
      (exponentiate r (n-1)
      ,r)

let calculate_userdef_depth_count
    (lc:LensContext.t)
    (r:regex)
    (v:id)
    (depth:int)
  : int =
  let rec calculate_userdef_depth_count_internal
      (r:regex)
      (depth:int)
    : int * int =
    begin match r with
      | RegExEmpty -> (0,0)
      | RegExBase _ -> (0,1)
      | RegExVariable s ->
        if depth = 0 && get_rep_userdef lc v = get_rep_userdef lc s then
          (1,1)
        else
          (0,1)
      | RegExOr (r1,r2) ->
        let (count1,width1) = calculate_userdef_depth_count_internal r1 depth in
        let (count2,width2) = calculate_userdef_depth_count_internal r2 depth in
        (count1+count2,width1+width2)
      | RegExConcat (r1,r2) ->
        let (count1,width1) = calculate_userdef_depth_count_internal r1 depth in
        let (count2,width2) = calculate_userdef_depth_count_internal r2 depth in
        (count1*width2 + count2*width1, width1*width2)
      | RegExStar r' ->
        let (count',_) = calculate_userdef_depth_count_internal r' (depth-1) in
        (count',1)
    end
  in
  fst (calculate_userdef_depth_count_internal r depth)

let rec calculate_or_width (r:regex) : int =
  begin match r with
    | RegExEmpty -> 0
    | RegExBase _ -> 1
    | RegExVariable _ -> 1
    | RegExOr (r1,r2) ->
      let r1_width = calculate_or_width r1 in
      let r2_width = calculate_or_width r2 in
      r1_width+r2_width
    | RegExConcat (r1,r2) ->
      let r1_width = calculate_or_width r1 in
      let r2_width = calculate_or_width r2 in
      r1_width*r2_width
    | RegExStar _ -> 1
  end


let calculate_userdef_distribution (lc:LensContext.t) (r:regex) : ((string * int) Counters.t) =
  let rec calculate_userdef_distribution_internal (r:regex) (depth:int)
    : ((string * int) Counters.t) * int =
      begin match r with
      | RegExEmpty -> (Counters.create comparison_compare,0)
      | RegExBase _ -> (Counters.create comparison_compare,1)
      | RegExVariable s ->
        if !use_lens_context then
          let rep_elt = fst (LensContext.shortest_path_to_rep_elt lc s) in
          (Counters.add
             (Counters.create (comparison_compare))
             (rep_elt,depth),1)
        else
          (Counters.add
             (Counters.create (comparison_compare))
             (s,depth),1)
      | RegExOr (r1,r2) ->
          let (counters_r1,width1) =
            calculate_userdef_distribution_internal r1 depth in
          let (counters_r2,width2) =
            calculate_userdef_distribution_internal r2 depth in
          (Counters.merge (fun x y -> x + y) counters_r1 counters_r2,width1+width2)
      | RegExConcat (r1,r2) ->
          let (counters_r1,width1) =
            calculate_userdef_distribution_internal r1 depth in
          let (counters_r2,width2) =
            calculate_userdef_distribution_internal r2 depth in
          (Counters.merge (fun x y -> (x*width2 + y*width1)) counters_r1
          counters_r2,width1*width2)
      | RegExStar r' ->
          (fst (calculate_userdef_distribution_internal r' (depth+1)),1)
      end
  in
  fst (calculate_userdef_distribution_internal r 0)
  (*let rec calculate_atom_userdef_distribution (a:atom) (depth:int) : (string * int) Counters.t =
    begin match a with
    | AUserDefined s ->
        Counters.add
          (Counters.create (comparison_compare))
          (s,depth)
    | AStar r' -> calculate_dnf_userdef_distribution r' (depth+1)
    end
  and calculate_clause_userdef_distribution ((atoms,strings):clause) (depth:int) : (string * int) Counters.t =
    List.fold_left
      ~f:(fun acc a ->
        Counters.merge
          acc
          (calculate_atom_userdef_distribution a depth))
      ~init:(Counters.create comparison_compare)
      atoms
  and calculate_dnf_userdef_distribution (clauses:dnf_regex) (depth:int) : (string * int) Counters.t =
    List.fold_left
      ~f:(fun acc c ->
        Counters.merge
          acc
          (calculate_clause_userdef_distribution c depth))
      ~init:(Counters.create comparison_compare)
      clauses
  in

  calculate_dnf_userdef_distribution (to_dnf_regex r) 0*)

  (*begin match r with
  | RegExBase _ -> Counters.create (comparison_compare)
  | RegExOr (r1,r2) ->
      let r1_counter = calculate_userdef_distribution r1 in
      let r2_counter = calculate_userdef_distribution r2 in
      Counters.merge r1_counter r2_counter
  | RegExConcat (r1,r2) ->
      let r1_counter = calculate_userdef_distribution r1 in
      let r2_counter = calculate_userdef_distribution r2 in
      Counters.merge r1_counter r2_counter
  | RegExStar (r') -> calculate_userdef_distribution r'
  | RegExVariable s ->
      Counters.add
        (Counters.create (comparison_compare))
        s
    end*)

let retrieve_distance (lc:LensContext.t) (r1:regex) (r2:regex) : int =
  let rec retrieve_distance_internal (cs1:((string * int) * int) list)
      (cs2:((string * int) * int) list)
    : int =
    begin match (cs1,cs2) with
      | ((s1,c1)::t1,(s2,c2)::t2) ->
        begin match comparison_compare s1 s2 with
          | EQ -> ((abs (c1 - c2))) +
                  (retrieve_distance_internal t1 t2)
          | LT -> (c1) +
                  (retrieve_distance_internal t1 cs2)
          | GT -> (c2) +
                  (retrieve_distance_internal cs1 t2)
        end
      | (_,[]) ->
        List.fold_left
          ~f:(fun acc (_,c) -> (c) + acc)
          ~init:0
          cs1
      | ([],_) ->
        List.fold_left
          ~f:(fun acc (_,c) -> (c) + acc)
          ~init:0
          cs2
    end
  in
  let userdef_dist_r1 = Counters.as_ordered_assoc_list
      (calculate_userdef_distribution lc r1) in
  let userdef_dist_r2 = Counters.as_ordered_assoc_list
      (calculate_userdef_distribution lc r2) in
  (retrieve_distance_internal
      userdef_dist_r1
      userdef_dist_r2)

let retrieve_priority (expansions_preformed:int): int =
  expansions_preformed

let rec quotiented_star (r:regex) (n:int) : regex =
  if n < 1 then
    failwith "invalid modulation"
  else if n = 1 then
    empty_string
  else
    RegExOr
      ((quotiented_star r (n-1))
      ,(exponentiate r (n-1)))

let empty_or_not_star_expansion_right (r:regex) : regex =
  RegExOr
    (RegExBase ""
    ,RegExConcat
      (RegExStar r
      ,r))


let empty_or_not_star_expansion_left (r:regex) : regex =
  RegExOr
    (RegExBase ""
    ,RegExConcat
      (r
      ,RegExStar r))

let quotient_product_expansion_right (n:int) (r:regex) : regex =
  RegExConcat
    ((quotiented_star r n)
    ,(RegExStar
      (exponentiate r n)))

let quotient_product_expansion_left (n:int) (r:regex) : regex =
  RegExConcat
    ((RegExStar
      (exponentiate r n))
    ,(quotiented_star r n))

let expand_stars (transformation:regex -> regex) (r:regex) : regex list =
  (*let transformations = empty_or_not_star_expansion_left::
    empty_or_not_star_expansion_right::
    List.concat_map
      ~f:(fun p ->
        [quotient_product_expansion_left p;
         quotient_product_expansion_right p])
      relevant_primes in*)
  let rec expand_stars_internal (r:regex) : regex list =
    begin match r with
    | RegExEmpty -> []
    | RegExBase _ -> []
    | RegExConcat (r1,r2) ->
        let r1_expansions = expand_stars_internal r1 in
        let r2_expansions = expand_stars_internal r2 in
        (List.map
          ~f:(fun expansion -> RegExConcat (expansion,r2))
          r1_expansions)
        @
        (List.map
          ~f:(fun expansion -> RegExConcat (r1,expansion))
          r2_expansions)
    | RegExOr (r1,r2) ->
        let r1_expansions = expand_stars_internal r1 in
        let r2_expansions = expand_stars_internal r2 in
        (List.map
          ~f:(fun expansion -> RegExOr (expansion,r2))
          r1_expansions)
        @
        (List.map
          ~f:(fun expansion -> RegExOr (r1,expansion))
          r2_expansions)
    | RegExStar (r') ->
        (transformation r')::
        (List.map ~f:(fun r'' -> RegExStar r'') (expand_stars_internal r'))
    | RegExVariable _ -> []
    end
  in
  expand_stars_internal r

let rec expand_userdefs (c:RegexContext.t) (r:regex)
                            : regex list =
  begin match r with
  | RegExEmpty -> []
  | RegExBase _ -> []
  | RegExConcat (r1,r2) ->
      let r1_expansions = expand_userdefs c r1 in
      let r2_expansions = expand_userdefs c r2 in
      (List.map
        ~f:(fun expansion -> RegExConcat (expansion,r2))
        r1_expansions)
      @
      (List.map
        ~f:(fun expansion -> RegExConcat (r1,expansion))
        r2_expansions)
  | RegExOr (r1,r2) ->
      let r1_expansions = expand_userdefs c r1 in
      let r2_expansions = expand_userdefs c r2 in
      (List.map
        ~f:(fun expansion -> RegExOr (expansion,r2))
        r1_expansions)
      @
      (List.map
        ~f:(fun expansion -> RegExOr (r1,expansion))
        r2_expansions)
  | RegExStar (r') ->
      List.map
        ~f:(fun expansion -> RegExStar expansion)
        (expand_userdefs c r')
  | RegExVariable t ->
      begin match RegexContext.lookup_for_expansion_exn c t with
      | Some rex -> [rex]
      | None -> []
      end
  end

module RegexSet = Comparison_set.Make(
  struct
    type element = regex
    let compare = regex_compare
    let to_string = regex_to_string
  end)

module StringSet = Comparison_set.Make(
  struct
    type element = string
    let compare = string_compare
    let to_string = ident
  end)

module IntSet = Comparison_set.Make(
  struct
    type element = int
    let compare = int_compare
    let to_string = string_of_int
  end)

module StringIntSet = Comparison_set.Make(
  struct
    type element = string * int
    let compare = pair_compare string_compare int_compare
    let to_string = string_of_pair ident string_of_int
  end)

module RegexRegexSet = Comparison_set.Make(
  struct
    type element = regex * regex
    let compare = pair_compare regex_compare regex_compare
    let to_string = string_of_pair regex_to_string regex_to_string
  end)

module StringToIntSetDict = Dict.Make(
  struct
    type key = string
    type value = IntSet.set
    let compare_key = string_compare
    let compare_value = IntSet.compare
    let key_to_string = ident
    let value_to_string = IntSet.to_string
  end)

module StringIntToIntDict = Dict.Make(
  struct
    type key = string * int
    type value = int
    let compare_key = pair_compare string_compare int_compare
    let compare_value = int_compare
    let key_to_string = string_of_pair ident string_of_int
    let value_to_string = string_of_int
  end)

let rec get_current_level_user_defined_rep_set
    (lc:LensContext.t)
    (r:regex)
  : StringSet.set =
  begin match r with
    | RegExEmpty -> StringSet.empty
    | RegExBase _ -> StringSet.empty
    | RegExConcat (r1,r2) ->
      let s1 = get_current_level_user_defined_rep_set lc r1 in
      let s2 = get_current_level_user_defined_rep_set lc r2 in
      StringSet.union s1 s2
    | RegExOr (r1,r2) ->
      let s1 = get_current_level_user_defined_rep_set lc r1 in
      let s2 = get_current_level_user_defined_rep_set lc r2 in
      StringSet.union s1 s2
    | RegExStar r' -> get_current_level_user_defined_rep_set lc r'
    | RegExVariable v ->
      StringSet.singleton
        (get_rep_userdef
           lc
           v)
  end

let expanded_form_po_compare
    (_:RegexContext.t)
    (_:LensContext.t)
    (_:string)
    (_:regex)
  : partial_order_comparison =
  failwith "ah"

let rec force_expand_userdef
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (v:string)
    (r:regex)
  : regex * int =
  begin match r with
    | RegExVariable v' ->
      if get_rep_userdef lc v' = v then
        begin match RegexContext.lookup_for_expansion_exn rc v' with
          | None -> failwith ("no solution: " ^ v')
          | Some r' -> (r',1)
        end
      else
        (r,0)
    | RegExConcat (r1,r2) ->
      let (r1_expanded,r1_exps) = force_expand_userdef rc lc v r1 in
      let (r2_expanded,r2_exps) = force_expand_userdef rc lc v r2 in
      (RegExConcat (r1_expanded,r2_expanded), r1_exps+r2_exps)
    | RegExOr (r1,r2) ->
      let (r1_expanded,r1_exps) = force_expand_userdef rc lc v r1 in
      let (r2_expanded,r2_exps) = force_expand_userdef rc lc v r2 in
      (RegExOr (r1_expanded,r2_expanded), r1_exps+r2_exps)
    | RegExStar r' ->
      let (r'_expanded,r'_exps) = force_expand_userdef rc lc v r' in
      (RegExStar r'_expanded, r'_exps)
    | RegExBase _ -> (r,0)
    | RegExEmpty -> (r,0)
  end

let rec expose_userdef
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (v:string)
    (r:regex)
  : (regex * int) list =
  begin match r with
    | RegExVariable v' ->
      if get_rep_userdef lc v' = v then
        [(RegExVariable v',0)]
      else
        begin match RegexContext.lookup_for_expansion_exn rc v' with
          | None -> []
          | Some r' ->
            List.map
              ~f:(fun (r,exp) -> (r,exp+1))
              (expose_userdef
                 rc
                 lc
                 v
                 r')
        end
    | RegExConcat (r1,r2) ->
      let r1_exposes = expose_userdef rc lc v r1 in
      let r2_exposes = expose_userdef rc lc v r2 in
      (List.map
         ~f:(fun (r1e,exp) -> (RegExConcat (r1e,r2),exp))
         r1_exposes)
      @
      (List.map
         ~f:(fun (r2e,exp) -> (RegExConcat (r1,r2e),exp))
         r2_exposes)
    | RegExOr (r1,r2) ->
      let r1_exposes = expose_userdef rc lc v r1 in
      let r2_exposes = expose_userdef rc lc v r2 in
      (List.map
         ~f:(fun (r1e,exp) -> (RegExOr (r1e,r2),exp))
         r1_exposes)
      @
      (List.map
         ~f:(fun (r2e,exp) -> (RegExOr (r1,r2e),exp))
         r2_exposes)
    | RegExStar r' ->
      let r'_exposes = expose_userdef rc lc v r' in
      (List.map
         ~f:(fun (r'e,exp) -> (RegExStar r'e,exp))
         r'_exposes)
    | RegExEmpty -> []
    | RegExBase _ -> []
  end

module ExpansionCountPQueue = Priority_queue_two.Make(
  struct
    type element = regex * regex * int
    let compare = triple_compare regex_compare regex_compare comparison_compare
    let priority (_,_,exps) = exps
    let to_string = string_of_triple regex_to_string regex_to_string string_of_int
  end)

let get_full_current_level_user_defined_rep_set
    (lc:LensContext.t)
    (r:regex)
  : StringIntSet.set =
  let rec get_current_level_user_defined_rep_set_internal
      (lc:LensContext.t)
      (r:regex)
      (depth:int)
    : StringIntSet.set =
    begin match r with
      | RegExEmpty -> StringIntSet.empty
      | RegExBase _ -> StringIntSet.empty
      | RegExConcat (r1,r2) ->
        let s1 =
          get_current_level_user_defined_rep_set_internal
            lc
            r1
            depth
        in
        let s2 =
          get_current_level_user_defined_rep_set_internal
            lc
            r2
            depth
        in
        StringIntSet.union s1 s2
      | RegExOr (r1,r2) ->
        let s1 =
          get_current_level_user_defined_rep_set_internal
            lc
            r1
            depth
        in
        let s2 =
          get_current_level_user_defined_rep_set_internal
            lc
            r2
            depth
        in
        StringIntSet.union s1 s2
      | RegExStar r' ->
        get_current_level_user_defined_rep_set_internal
          lc
          r'
          (depth+1)
      | RegExVariable v ->
        let v' = get_rep_userdef lc v in
        StringIntSet.singleton
          (v',depth)
    end
  in
  get_current_level_user_defined_rep_set_internal
    lc
    r
    0

let requires_full_expansions (lc:LensContext.t) (r1:regex) (r2:regex)
  : bool =
  let s1 = get_full_current_level_user_defined_rep_set lc r1 in
  let s2 = get_full_current_level_user_defined_rep_set lc r2 in
  let problem_elements =
    (List.map
       ~f:(fun e -> Left e)
       (StringIntSet.as_list (StringIntSet.minus s1 s2)))
    @
    (List.map
       ~f:(fun e -> Right e)
       (StringIntSet.as_list (StringIntSet.minus s2 s1)))
  in
  not (List.is_empty problem_elements)

let requires_simple_expansions
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r1:regex)
    (r2:regex)
  : bool =
  let rec retrieve_transitive_userdefs (r:regex) : string list =
    begin match r with
      | RegExEmpty -> []
      | RegExBase _ -> []
      | RegExConcat (r1,r2) -> (retrieve_transitive_userdefs r1) @
                               (retrieve_transitive_userdefs r2)
    | RegExOr (r1,r2) -> (retrieve_transitive_userdefs r1) @
        (retrieve_transitive_userdefs r2)
    | RegExStar r' -> retrieve_transitive_userdefs r'
    | RegExVariable t -> (get_rep_userdef lc t)::
      (begin match RegexContext.lookup_for_expansion_exn rc t with
      | None -> []
      | Some rex -> retrieve_transitive_userdefs rex
      end)
    end
  in
  let r1_transitive_userdefs = retrieve_transitive_userdefs r1 in
  let r2_transitive_userdefs = retrieve_transitive_userdefs r2 in
  let r1_userdefs = StringSet.as_list (get_current_level_user_defined_rep_set lc r1) in
  let r2_userdefs = StringSet.as_list (get_current_level_user_defined_rep_set lc r2) in
  let r1_not_in_r2trans = set_minus_lose_order comparison_compare
      r1_userdefs
      r2_transitive_userdefs in
  let r2_not_in_r1trans = set_minus_lose_order comparison_compare
      r2_userdefs
      r1_transitive_userdefs in
  not (List.is_empty (r1_not_in_r2trans@r2_not_in_r1trans))


let expand_full_outermost_required_expansions (rc:RegexContext.t) (lc:LensContext.t) (r1:regex) (r2:regex)
  : (regex * regex * int) =
  let expand_full_outermost_required_expansions_internal
      (rc:RegexContext.t)
      (lc:LensContext.t)
      ((r1,r2,exps):regex * regex * int)
    : regex * regex * int =
    let rec retrieve_full_transitive_userdefs (r:regex) (star_depth:int) : (string * int) list =
      begin match r with
        | RegExEmpty -> []
        | RegExBase _ -> []
        | RegExConcat (r1,r2) -> (retrieve_full_transitive_userdefs r1 star_depth) @
                                 (retrieve_full_transitive_userdefs r2 star_depth)
        | RegExOr (r1,r2) -> (retrieve_full_transitive_userdefs r1 star_depth) @
                             (retrieve_full_transitive_userdefs r2 star_depth)
        | RegExStar r' -> retrieve_full_transitive_userdefs r' (star_depth+1)
        | RegExVariable t -> (get_rep_userdef lc t, star_depth)::
                             (begin match RegexContext.lookup_for_expansion_exn rc t with
                                | None -> []
                                | Some rex -> retrieve_full_transitive_userdefs rex star_depth
                              end)
      end
    in
    let rec expand_full_required_expansions (bad_userdefs:(string * int) list)
        (r:regex)
        (star_depth:int)
      : regex * int =
      begin match r with
        | RegExEmpty -> (r,0)
        | RegExBase _ -> (r,0)
        | RegExConcat (r1,r2) ->
          let (r1',e1) = expand_full_required_expansions bad_userdefs r1 star_depth in
          let (r2',e2) = expand_full_required_expansions bad_userdefs r2 star_depth in
          (RegExConcat(r1',r2'),e1+e2)
        | RegExOr (r1,r2) -> 
          let (r1',e1) = expand_full_required_expansions bad_userdefs r1 star_depth in
          let (r2',e2) = expand_full_required_expansions bad_userdefs r2 star_depth in
          (RegExOr(r1',r2'),e1+e2)
        | RegExStar r' ->
          let (r'',e') = expand_full_required_expansions bad_userdefs r' (star_depth+1) in
          (RegExStar(r''),e')
        | RegExVariable t ->
          if List.mem bad_userdefs (t,star_depth) then
            begin match RegexContext.lookup_for_expansion_exn rc
                          (get_rep_userdef lc t) with
            | None -> failwith "no solution"
            | Some r' ->
              let (r'',e') = expand_full_required_expansions bad_userdefs r' star_depth in
              (r'',e'+1)
            end
          else
            (r,0)
      end
    in

    let r1_transitive_userdefs = retrieve_full_transitive_userdefs r1 0 in
    let r2_transitive_userdefs = retrieve_full_transitive_userdefs r2 0 in
    let all_userdefs =
      StringSet.from_list
        ((List.map ~f:fst r1_transitive_userdefs)
         @(List.map ~f:fst r2_transitive_userdefs))
    in
    let empty_depths_dict =
      List.fold_left
        ~f:(fun d v ->
            StringToIntSetDict.insert d v IntSet.empty)
        ~init:StringToIntSetDict.empty
        (StringSet.as_list all_userdefs)
    in
    let r1_depths =
      List.fold_left
        ~f:(fun d (v,depth) ->
            let previous_depths = StringToIntSetDict.lookup_exn d v in
            StringToIntSetDict.insert d v (IntSet.insert depth previous_depths))
        ~init:empty_depths_dict
        r1_transitive_userdefs
    in
    let r2_depths =
      List.fold_left
        ~f:(fun d (v,depth) ->
            let previous_depths = StringToIntSetDict.lookup_exn d v in
            StringToIntSetDict.insert d v (IntSet.insert depth previous_depths))
        ~init:empty_depths_dict
        r2_transitive_userdefs
    in

    let unreachables =
      List.fold_left
        ~f:(fun acc v ->
            let r1_depth_list =
              IntSet.as_list
                (StringToIntSetDict.lookup_exn
                   r1_depths
                   v)
            in
            let r2_depth_list =
              IntSet.as_list
                (StringToIntSetDict.lookup_exn
                   r2_depths
                   v)
            in
            let not_accessible_in_r1_list =
              List.filter
                ~f:(fun d ->
                    List.for_all ~f:(fun d' -> d > d') r2_depth_list)
                r1_depth_list
            in
            let not_accessible_in_r2_list =
              List.filter
                ~f:(fun d ->
                    List.for_all ~f:(fun d' -> d > d') r1_depth_list)
                r2_depth_list
            in
            (List.map
               ~f:(fun d -> Left (v,d))
               not_accessible_in_r1_list)
            @
            (List.map
               ~f:(fun d -> Right (v,d))
               not_accessible_in_r2_list)
            @
            acc)
        ~init:[]
        (StringSet.as_list all_userdefs)
    in
    let (left_unreachables,right_unreachables) = split_by_either unreachables in
    begin match (expand_full_required_expansions left_unreachables r1 0,
                 expand_full_required_expansions right_unreachables r2 0) with
    | ((r1',e1),(r2',e2)) -> (r1',r2',e1+e2+exps)
    end
  in
  fold_until_fixpoint
    (expand_full_outermost_required_expansions_internal
       rc
       lc)
    (r1,r2,0)


let expand_outermost_required_expansions (rc:RegexContext.t) (lc:LensContext.t) (r1:regex) (r2:regex)
  : (regex * regex * int) =
  let rec retrieve_transitive_userdefs (r:regex) : string list =
    begin match r with
      | RegExEmpty -> []
      | RegExBase _ -> []
      | RegExConcat (r1,r2) -> (retrieve_transitive_userdefs r1) @
                               (retrieve_transitive_userdefs r2)
    | RegExOr (r1,r2) -> (retrieve_transitive_userdefs r1) @
        (retrieve_transitive_userdefs r2)
    | RegExStar r' -> retrieve_transitive_userdefs r'
    | RegExVariable t -> (get_rep_userdef lc t)::
      (begin match RegexContext.lookup_for_expansion_exn rc t with
      | None -> []
      | Some rex -> retrieve_transitive_userdefs rex
      end)
    end
  in
  let rec expand_required_expansions (bad_userdefs:string list)
                                 (r:regex)
    : regex * int =
    begin match r with
    | RegExEmpty -> (r,0)
    | RegExBase _ -> (r,0)
    | RegExConcat (r1,r2) ->
      let (r1',e1) = expand_required_expansions bad_userdefs r1 in
      let (r2',e2) = expand_required_expansions bad_userdefs r2 in
      (RegExConcat(r1',r2'),e1+e2)
    | RegExOr (r1,r2) -> 
      let (r1',e1) = expand_required_expansions bad_userdefs r1 in
      let (r2',e2) = expand_required_expansions bad_userdefs r2 in
      (RegExOr(r1',r2'),e1+e2)
    | RegExStar r' ->
      let (r'',e') = expand_required_expansions bad_userdefs r' in
      (RegExStar(r''),e')
    | RegExVariable t ->
        if List.mem bad_userdefs t then
          begin match RegexContext.lookup_for_expansion_exn rc
                        (get_rep_userdef lc t) with
          | None -> failwith "no solution"
          | Some r' ->
            let (r'',e') = expand_required_expansions bad_userdefs r' in
            (r'',e'+1)
          end
        else
          (r,0)
    end
  in

  let r1_transitive_userdefs = retrieve_transitive_userdefs r1 in
  let r2_transitive_userdefs = retrieve_transitive_userdefs r2 in
  let r1trans_not_in_r2trans = set_minus_lose_order comparison_compare
      r1_transitive_userdefs
      r2_transitive_userdefs in
  let r2trans_not_in_r1trans = set_minus_lose_order comparison_compare
      r2_transitive_userdefs
      r1_transitive_userdefs in
  begin match (expand_required_expansions r1trans_not_in_r2trans r1,
               expand_required_expansions r2trans_not_in_r1trans r2) with
  | ((r1',e1),(r2',e2)) -> (r1',r2',e1+e2)
  end

let rec expose_full_userdef
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (v:string)
    (star_depth:int)
    (r:regex)
  : (regex * int) list =
  begin match r with
    | RegExVariable v' ->
      if get_rep_userdef lc v' = v && star_depth = 0 then
        [(RegExVariable v',0)]
      else
        begin match RegexContext.lookup_for_expansion_exn rc v' with
          | None -> []
          | Some r' ->
            List.map
              ~f:(fun (r,exp) -> (r,exp+1))
              (expose_full_userdef
                 rc
                 lc
                 v
                 star_depth
                 r')
        end
    | RegExConcat (r1,r2) ->
      let r1_exposes = expose_full_userdef rc lc v star_depth r1 in
      let r2_exposes = expose_full_userdef rc lc v star_depth r2 in
      (List.map
         ~f:(fun (r1e,exp) -> (RegExConcat (r1e,r2),exp))
         r1_exposes)
      @
      (List.map
         ~f:(fun (r2e,exp) -> (RegExConcat (r1,r2e),exp))
         r2_exposes)
    | RegExOr (r1,r2) ->
      let r1_exposes = expose_full_userdef rc lc v star_depth r1 in
      let r2_exposes = expose_full_userdef rc lc v star_depth r2 in
      (List.map
         ~f:(fun (r1e,exp) -> (RegExOr (r1e,r2),exp))
         r1_exposes)
      @
      (List.map
         ~f:(fun (r2e,exp) -> (RegExOr (r1,r2e),exp))
         r2_exposes)
    | RegExStar r' ->
      let r'_exposes_with_unfold =
        expose_full_userdef
          rc
          lc
          v
          star_depth
          r'
      in
      let r'_exposes_underneath =
        expose_full_userdef
          rc
          lc
          v
          (star_depth-1)
          r'
      in
      let star_r'_exposes_underneath =
        (List.map
           ~f:(fun (r'e,exp) -> (RegExStar r'e,exp))
           r'_exposes_underneath)
      in
      let unrolled_r'_exposes_left =
        (List.map
           ~f:(fun (r'e,exp) -> (RegExOr(RegExBase "", RegExConcat (r'e, RegExStar r'e)) ,exp+1))
           r'_exposes_with_unfold)
      in
      let unrolled_r'_exposes_right =
        (List.map
           ~f:(fun (r'e,exp) -> (RegExOr(RegExBase "", RegExConcat (RegExStar r'e, r'e)) ,exp+1))
           r'_exposes_with_unfold)
      in
      star_r'_exposes_underneath@unrolled_r'_exposes_left@unrolled_r'_exposes_right
    | RegExEmpty -> []
    | RegExBase _ -> []
  end

let rec shrink_count_of_regex_depth
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r:regex)
    (v:id)
    (depth:int)
  : (regex * int) list =
  begin match r with
    | RegExEmpty -> []
    | RegExBase _ -> []
    | RegExConcat (r1,r2) ->
      let r1_shrinks = shrink_count_of_regex_depth rc lc r1 v depth in
      let r2_shrinks = shrink_count_of_regex_depth rc lc r2 v depth in
      (List.map
         ~f:(fun (r1',exs) -> (RegExConcat(r1',r2),exs))
         r1_shrinks)
      @
      (List.map
         ~f:(fun (r2',exs) -> (RegExConcat(r1,r2'),exs))
         r2_shrinks)
    | RegExOr (r1,r2) ->
      let r1_shrinks = shrink_count_of_regex_depth rc lc r1 v depth in
      let r2_shrinks = shrink_count_of_regex_depth rc lc r2 v depth in
      (List.map
         ~f:(fun (r1',exs) -> (RegExOr(r1',r2),exs))
         r1_shrinks)
      @
      (List.map
         ~f:(fun (r2',exs) -> (RegExOr(r1,r2'),exs))
         r2_shrinks)
    | RegExStar r' ->
      let r'_shrinks = shrink_count_of_regex_depth rc lc r' v (depth-1) in
      List.map
        ~f:(fun (r'',exs) -> (RegExStar(r''),exs))
        r'_shrinks
    | RegExVariable s ->
      if depth = 0 && get_rep_userdef lc v = get_rep_userdef lc s then
        begin match RegexContext.lookup_for_expansion_exn rc s with
          | Some r -> [(r,1)]
          | None -> []
        end
      else
        []
  end

let expand_regex_once
    (rc:RegexContext.t)
    (r:regex)
  : regex list =

  let expanders =
    [(expand_userdefs rc)
    ;(expand_stars empty_or_not_star_expansion_right)
    ;(expand_stars empty_or_not_star_expansion_left)]
  in

  List.concat_map
    ~f:(fun exp -> exp r)
    expanders

let expand_count_of_regex_depth
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r:regex)
    (v:id)
    (depth:int)
  : (regex * int) list =
  let rec expand_count_of_regex_depth_internal
      (r:regex)
      (depth:int)
    : (regex * int) list =
    begin match r with
      | RegExEmpty -> []
      | RegExBase _ -> []
      | RegExConcat (r1,r2) ->
        let expanded_r1_r =
          if (calculate_userdef_depth_count lc r2 v depth > 0) then
            let expanded_r1 =
              expand_regex_once
                rc
                r1
            in
            List.map
              ~f:(fun r1' -> (RegExConcat(r1',r2),1))
              expanded_r1
          else
            []
        in
        let expanded_r2_r =
          if (calculate_userdef_depth_count lc r1 v depth > 0) then
            let expanded_r2 =
              expand_regex_once
                rc
                r2
            in
            List.map
              ~f:(fun r2' -> (RegExConcat(r1,r2'),1))
              expanded_r2
          else
            []
        in
        let recursive_r1_r =
          List.map
            ~f:(fun (r1',exps) -> (RegExConcat(r1',r2),exps))
            (expand_count_of_regex_depth_internal r1 depth)
        in
        let recursive_r2_r =
          List.map
            ~f:(fun (r2',exps) -> (RegExConcat(r1,r2'),exps))
            (expand_count_of_regex_depth_internal r2 depth)
        in
        recursive_r1_r@recursive_r2_r@expanded_r1_r@expanded_r2_r
      | RegExOr (r1,r2) ->
        (List.map
           ~f:(fun (r1',exps) -> (RegExOr(r1',r2),exps))
           (expand_count_of_regex_depth_internal r1 depth))
        @
        (List.map
           ~f:(fun (r2',exps) -> (RegExOr(r1,r2'),exps))
           (expand_count_of_regex_depth_internal r2 depth))
      | RegExStar r' ->
        let r'_increase_with_unfold =
          expand_count_of_regex_depth_internal
            r'
            depth
        in
        let r'_increase_underneath =
          expand_count_of_regex_depth_internal
            r'
            (depth-1)
        in
        let star_r'_increase_underneath =
          (List.map
             ~f:(fun (r'e,exp) -> (RegExStar r'e,exp))
             r'_increase_underneath)
        in
        let unrolled_r'_increase_left =
          (List.map
             ~f:(fun (r'e,exp) -> (RegExOr(RegExBase "", RegExConcat (r'e, RegExStar r'e)) ,exp+1))
             r'_increase_with_unfold)
        in
        let unrolled_r'_increase_right =
          (List.map
             ~f:(fun (r'e,exp) -> (RegExOr(RegExBase "", RegExConcat (RegExStar r'e, r'e)) ,exp+1))
             r'_increase_with_unfold)
        in
        star_r'_increase_underneath@unrolled_r'_increase_left@unrolled_r'_increase_right
      | RegExVariable s ->
        if depth = 0 && get_rep_userdef lc s = get_rep_userdef lc v then
          [(RegExVariable s,0)]
        else
          begin match RegexContext.lookup_for_expansion_exn rc s with
            | None -> []
            | Some r' ->
              List.map
                ~f:(fun (x,exp) -> (x,exp+1))
                (expand_count_of_regex_depth_internal
                   r'
                   depth)
          end
    end
  in
  List.filter
    ~f:(fun (_,exps) -> exps <> 0)
    (expand_count_of_regex_depth_internal r depth)


let make_userdef_depth_same_size
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r1:regex)
    (r2:regex)
    (v:id)
    (depth:int)
  : (regex * regex * int) list =
  let make_userdef_depth_same_size_internal
      (to_process:ExpansionCountPQueue.queue)
    : (regex * regex * int) list =
    let ((r1,r2,exs),_,to_process) = ExpansionCountPQueue.pop_exn to_process in
    let (r1,r2,exs') = expand_full_outermost_required_expansions rc lc r1 r2 in
    let exs = exs + exs' in
    let count_left = calculate_userdef_depth_count lc r1 v depth in
    let count_right = calculate_userdef_depth_count lc r2 v depth in
    begin match int_compare count_left count_right with
      | EQ ->
        (r1,r2,exs)::
        (List.filter_map
           ~f:(fun ((r1,r2,exs),_) ->
               let count_left = calculate_userdef_depth_count lc r1 v depth in
               let count_right = calculate_userdef_depth_count lc r2 v depth in
               begin match int_compare count_left count_right with
                 | EQ -> Some (r1,r2,exs)
                 | _ -> None
               end)
           (ExpansionCountPQueue.all_remaining to_process))
      | LT ->
        let expanded_r1s =
          expand_count_of_regex_depth
            rc
            lc
            r1
            v
            depth
        in
        let shrunk_r2s =
          shrink_count_of_regex_depth
            rc
            lc
            r2
            v
            depth
        in
        (List.map
           ~f:(fun (r1',exps) -> (r1',r2,exps+exs))
           expanded_r1s)
        @
        (List.map
           ~f:(fun (r2',exps) -> (r1,r2',exps+exs))
           shrunk_r2s)
      | GT ->
        let shrunk_r1s =
          shrink_count_of_regex_depth
            rc
            lc
            r1
            v
            depth
        in
        let expanded_r2s =
          expand_count_of_regex_depth
            rc
            lc
            r2
            v
            depth
        in
        (List.map
           ~f:(fun (r1',exps) -> (r1',r2,exps+exs))
           shrunk_r1s)
        @
        (List.map
           ~f:(fun (r2',exps) -> (r1,r2',exps+exs))
           expanded_r2s)
    end
  in
  make_userdef_depth_same_size_internal (ExpansionCountPQueue.singleton (r1,r2,0))


let expand_evening_required_expansions
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r1:regex)
    (r2:regex)
  : (regex * regex * int) list =
  let rec expand_real_required_expansions_internal
      (to_process:ExpansionCountPQueue.queue)
    : (regex * regex * int) list =
    let ((r1,r2,exs),_,to_process) = ExpansionCountPQueue.pop_exn to_process in
    let (r1,r2,exs') = expand_full_outermost_required_expansions rc lc r1 r2 in
    let exs = exs + exs' in
    (*print_endline (regex_to_string r1);
      print_endline (regex_to_string r2);
      print_endline (string_of_int exs);
      print_endline "\n\n";*)
    let dist1 = calculate_userdef_distribution lc r1 in
    let dist2 = calculate_userdef_distribution lc r2 in
    let map1 =
      StringIntToIntDict.from_kvp_list
        (Counters.as_ordered_assoc_list dist1)
    in
    let map2 =
      StringIntToIntDict.from_kvp_list
        (Counters.as_ordered_assoc_list dist2)
    in
    let all_userdef_depths =
      StringIntSet.from_list
        ((StringIntToIntDict.key_list map1)
         @(StringIntToIntDict.key_list map2))
    in
    let all_tasks =
      List.filter
        ~f:(fun (v,depth) ->
            let r1_count =
              begin match StringIntToIntDict.lookup map1 (v,depth) with
                | None -> 0
                | Some i -> i
              end
            in
            let r2_count =
              begin match StringIntToIntDict.lookup map2 (v,depth) with
                | None -> 0
                | Some i -> i
              end
            in
            begin match int_compare r1_count r2_count with
              | EQ -> false
              | _  -> true
            end)
        (StringIntSet.as_list all_userdef_depths)
    in
    if List.is_empty all_tasks then
      let other_possibilities =
        List.filter
          ~f:(fun (r1,r2,_) -> retrieve_distance lc r1 r2 = 0)
          (List.map
             ~f:fst
             (ExpansionCountPQueue.all_remaining to_process))
      in
      (r1,r2,exs)::other_possibilities
    else
      let new_problems =
        List.concat_map
          ~f:(fun (v,depth) ->
              make_userdef_depth_same_size
                rc
                lc
                r1
                r2
                v
                depth)
          all_tasks
      in
      expand_real_required_expansions_internal
        (ExpansionCountPQueue.push_all to_process new_problems)
  in
  expand_real_required_expansions_internal
    (ExpansionCountPQueue.singleton (r1,r2,0))

let expand_deeper_required_expansions
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r1:regex)
    (r2:regex)
  : (regex * regex * int) list =
  let rec expand_real_required_expansions_internal
      (to_process:ExpansionCountPQueue.queue)
    : (regex * regex * int) list =
    let ((r1,r2,exs),_,to_process) = ExpansionCountPQueue.pop_exn to_process in
    let (r1,r2,exs') = expand_full_outermost_required_expansions rc lc r1 r2 in
    let exs = exs + exs' in
    (*print_endline (regex_to_string r1);
      print_endline (regex_to_string r2);
      print_endline (string_of_int exs);
      print_endline "\n\n";*)
    let s1 = get_full_current_level_user_defined_rep_set lc r1 in
    let s2 = get_full_current_level_user_defined_rep_set lc r2 in
    let problem_elements =
      (List.map
         ~f:(fun e -> Left e)
         (StringIntSet.as_list (StringIntSet.minus s1 s2)))
      @
      (List.map
         ~f:(fun e -> Right e)
         (StringIntSet.as_list (StringIntSet.minus s2 s1)))
    in
    if List.is_empty problem_elements then
      let other_possibilities =
        List.map
          ~f:fst
          (ExpansionCountPQueue.all_remaining to_process)
      in
      (r1,r2,exs)::other_possibilities
    else
      let new_problems =
        List.concat_map
          ~f:(fun se ->
              begin match se with
                | Left (v,star_depth) ->
                  let exposes = expose_full_userdef rc lc v star_depth r2 in
                  if List.is_empty exposes then
                    let (r1_expanded,expcount) =
                      force_expand_userdef
                        rc
                        lc
                        v
                        r1
                    in
                    [(r1_expanded,r2,expcount+exs)]
                  else
                    List.map ~f:(fun (e,exp) -> (r1,e,exs+exp)) exposes
                | Right (v,star_depth) ->
                  let exposes = expose_full_userdef rc lc v star_depth r1 in
                  if List.is_empty exposes then
                    failwith ("shoulda handled earlier  " ^ v ^ "   " ^ (string_of_int star_depth) ^ "\n\n" ^ (Pp.boom_pp_regex r1)
                             ^ "\n\n" ^ (Pp.boom_pp_regex r2))
                    (*let (r2_expanded,expcount) =
                      force_expand_userdef
                        r
                      c
                        lc
                        v
                        r2
                    in
                      [(r1,r2_expanded,expcount+exs)]*)
                  else
                    List.map ~f:(fun (e,exp) -> (e,r2,exs+exp)) exposes
              end)
          problem_elements
      in
      expand_real_required_expansions_internal
        (ExpansionCountPQueue.push_all to_process new_problems)
  in
  expand_real_required_expansions_internal
    (ExpansionCountPQueue.singleton (r1,r2,0))

let expand_real_required_expansions
    (rc:RegexContext.t)
    (lc:LensContext.t)
    (r1:regex)
    (r2:regex)
  : (regex * regex * int) list =
  let rec expand_real_required_expansions_internal
      (to_process:ExpansionCountPQueue.queue)
    : (regex * regex * int) list =
    let ((r1,r2,exs),pri,to_process) = ExpansionCountPQueue.pop_exn to_process in
    let (r1,r2,exs') = expand_outermost_required_expansions rc lc r1 r2 in
    let exs = exs + exs' in
    (*print_endline (regex_to_string r1);
    print_endline (regex_to_string r2);
    print_endline (string_of_int exs);
      print_endline "\n\n";*)
    let s1 = get_current_level_user_defined_rep_set lc r1 in
    let s2 = get_current_level_user_defined_rep_set lc r2 in
    let problem_elements =
      (List.map
         ~f:(fun e -> Left e)
         (StringSet.as_list (StringSet.minus s1 s2)))
      @
      (List.map
         ~f:(fun e -> Right e)
         (StringSet.as_list (StringSet.minus s2 s1)))
    in
    if List.is_empty problem_elements then
      let other_possibilities =
        List.map
          ~f:fst
          (fst (ExpansionCountPQueue.pop_until_min_pri_greater_than to_process (10 * pri)))
      in
      (r1,r2,exs)::other_possibilities
    else
      let new_problems =
        List.concat_map
          ~f:(fun se ->
              begin match se with
                | Left v ->
                  let exposes = expose_userdef rc lc v r2 in
                  if List.is_empty exposes then
                    let (r1_expanded,expcount) =
                      force_expand_userdef
                        rc
                        lc
                        v
                        r1
                    in
                    [(r1_expanded,r2,expcount+exs)]
                  else
                    List.map ~f:(fun (e,exp) -> (r1,e,exs+exp)) exposes
                | Right v ->
                  let exposes = expose_userdef rc lc v r1 in
                  if List.is_empty exposes then
                    failwith ("shoulda handled earlier  " ^ v ^ "\n\n" ^ (Pp.boom_pp_regex r1)
                             ^ "\n\n" ^ (Pp.boom_pp_regex r2))
                    (*let (r2_expanded,expcount) =
                      force_expand_userdef
                        r
                      c
                        lc
                        v
                        r2
                    in
                      [(r1,r2_expanded,expcount+exs)]*)
                  else
                    List.map ~f:(fun (e,exp) -> (e,r2,exs+exp)) exposes
              end)
          problem_elements
      in
      expand_real_required_expansions_internal
        (ExpansionCountPQueue.push_all to_process new_problems)
  in
  expand_real_required_expansions_internal
    (ExpansionCountPQueue.singleton (r1,r2,0))

let retrieve_userdefs (r:regex) : id list =
  let rec retrieve_userdefs_internal (r:regex) : id list =
    begin match r with
      | RegExBase _ -> []
      | RegExConcat (r1,r2) ->
        (retrieve_userdefs_internal r1) @
        (retrieve_userdefs_internal r2)
      | RegExOr (r1,r2) ->
        (retrieve_userdefs_internal r1) @
        (retrieve_userdefs_internal r2)
      | RegExStar r' -> retrieve_userdefs_internal r'
      | RegExVariable u -> [u]
      | RegExEmpty -> []
    end
  in
  List.dedup (retrieve_userdefs_internal r)

let requires_userdef_expansions (r1:regex) (r2:regex) : bool =
  let r1_userdefs = retrieve_userdefs r1 in
  let r2_userdefs = retrieve_userdefs r2 in
  let r1_not_r2 =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  let r2_not_r1 =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  begin match (r1_not_r2,r2_not_r1) with
    | ([],[]) -> true
    | _ -> false
  end
  

let expand_once_to_queue_elts (_:int) (rc:RegexContext.t) (lc:LensContext.t) (r1:regex) (r2:regex)
(expansions_preformed:int)
                            : (queue_element * int) list =
  let retrieve_expansions_from_transform (transform:regex -> regex list):
    (regex * regex) list =
      (List.map
        ~f:(fun le -> (le, r2))
        (transform r1))
      @
      (List.map
        ~f:(fun re -> (r1, re))
        (transform r2))
  in

  let all_immediate_expansions =
    (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform
      (expand_stars empty_or_not_star_expansion_right))
    @ (retrieve_expansions_from_transform
      (expand_stars empty_or_not_star_expansion_left))
  in

  let turn_regex_double_into_queue_element_priority
    ((r1,r2):regex*regex)
    : queue_element * int =
    let distance = retrieve_distance lc r1 r2 in
    let priority = retrieve_priority expansions_preformed in
      (QERegexCombo
        (r1,r2,distance,expansions_preformed+1),
        priority)
  in


  let rec infinitary_expansion (min:int) (max:int) (_:unit)
    : (queue_element * int) list =
      let transformations =
        List.concat_map
        ~f:(fun p ->
          [expand_stars (quotient_product_expansion_left p);
          expand_stars (quotient_product_expansion_right p)])
        (primes_between min max)
      in
      (List.map
      ~f:turn_regex_double_into_queue_element_priority
      (List.concat_map
      ~f:(fun transform -> retrieve_expansions_from_transform transform)
      transformations))
      @
      [(QEGenerator (infinitary_expansion max (max + max-min)),max
      * 100)]
  in
(QEGenerator (infinitary_expansion 1 5),2)::
  (List.map
    ~f:turn_regex_double_into_queue_element_priority
    all_immediate_expansions)
  (*List.dedup
  (((List.map ~f:(fun le -> (le,r2)) left_expansions)
    @ (List.map ~f:(fun re -> (r1,re)) right_expansions)))*)

let search_expand_userdefs
    (_:RegexContext.t)
    (_:LensContext.t)
    (r1:regex)
    (r2:regex)
    (_:int)
  : (queue_element * float) list =
  let r1_userdefs = retrieve_userdefs r1 in
  let r2_userdefs = retrieve_userdefs r2 in
  let elements_r1_missing =
    set_minus_lose_order
      comparison_compare
      r1_userdefs
      r2_userdefs
  in
  if elements_r1_missing = [] then
    (*let elements_r2_missing = 
      set_minus_lose_order
        comparison_compare
        r2_userdefs
        r1_userdefs
    in
    let missing_count = List.length elements_r2_missing in*)
    []
  else
    []
  
  
let retrieve_transformation_queue_elements
        (max_size:int)
        (rc:RegexContext.t)
        (lc:LensContext.t)
        (r1:regex)
        (r2:regex)
        (expansions_preformed:int)
  : (queue_element * int) list =
  (expand_once_to_queue_elts max_size rc lc r1 r2 expansions_preformed)


let rec atom_lens_to_lens (a:atom_lens) : lens =
  begin match a with
    | AtomLensIterate d -> LensIterate (dnf_lens_to_lens d)
    | AtomLensVariable l -> l
  end

and clause_lens_to_lens ((atoms,permutation,strings1,strings2):clause_lens)
  : lens =
    let rec combine_scct_and_atom_lenses
            (atom_lenses:lens list)
            (scct:swap_concat_compose_tree)
            : (lens * lens list) =
      begin match scct with
      | SCCTSwap (s1,s2) ->
          let (l1,remaining_left) =
            combine_scct_and_atom_lenses
              atom_lenses
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              remaining_left
              s2 in
          (LensSwap(l1,l2),remaining_total)
      | SCCTConcat (s1,s2) ->
          let (l1,remaining_left) =
            combine_scct_and_atom_lenses
              atom_lenses
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              remaining_left
              s2 in
          (LensConcat(l1,l2),remaining_total)
      | SCCTCompose _ ->
        failwith "compose is too ugly, should have failed faster"
          (*let s2size = size_scct s2 in
          let identity_copies = duplicate (LensIdentity (RegExBase "TODO")) s2size in
          let (l1,_) =
            combine_scct_and_atom_lenses
              identity_copies
              s1 in
          let (l2,remaining_total) =
            combine_scct_and_atom_lenses
              atom_lenses
              s2 in
            (LensCompose(l1,l2),remaining_total)*)
      | SCCTLeaf -> split_by_first_exn atom_lenses
      end
    in
    let (string1h,string1t) = split_by_first_exn strings1 in
    let (string2h,string2t) = split_by_first_exn strings2 in
    let (string2t_invperm) =
      Permutation.apply_inverse_to_list_exn
        permutation
        string2t
    in
    let string_lss_hd = LensConst (string1h, string2h) in
    let string_tl_combos = List.zip_exn string1t string2t_invperm in
    let string_lss_tl =
      List.map
        ~f:(fun (x,y) -> LensConst (x,y))
        string_tl_combos
    in
    let atom_lenses =
      List.map ~f:atom_lens_to_lens atoms in
    let atom_string_zips = List.zip_exn atom_lenses string_lss_tl in
    let atom_string_concats =
      List.map ~f:(fun (x,y) -> LensConcat (x,y)) atom_string_zips in
    begin match atom_string_concats with
    | [] -> string_lss_hd
    | _ ->
      let permutation_scct =
        Permutation.to_swap_concat_compose_tree permutation in
      if has_compose permutation_scct then
        LensConcat(string_lss_hd,
                   LensPermute (permutation,atom_string_concats))
      else
        LensConcat(string_lss_hd,
                   (fst (combine_scct_and_atom_lenses
                           atom_string_concats
                           permutation_scct)))
    end

and dnf_lens_to_lens ((clauses,_):dnf_lens) : lens =
  let clause_lenses = List.map ~f:clause_lens_to_lens clauses in
  List.fold_left
    ~f:(fun acc l -> LensUnion (acc, l))
    ~init:(LensIdentity (RegExEmpty))
    clause_lenses
    

let rec iteratively_deepen (r:regex) : regex * RegexContext.t =
  begin match r with
  | RegExEmpty -> (r,RegexContext.empty)
  | RegExBase _ -> (r,RegexContext.empty)
  | RegExConcat (r1,r2) ->
      let (r1',c1) = iteratively_deepen r1 in
      let (r2',c2) = iteratively_deepen r2 in
      let context = RegexContext.merge_contexts_exn c1 c2 in
      let regex_definition = RegExConcat(r1',r2') in
      let regex_variable =
        RegexContext.autogen_id
          context
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          context
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExOr (r1,r2) ->
      let (r1',c1) = iteratively_deepen r1 in
      let (r2',c2) = iteratively_deepen r2 in
      let context = RegexContext.merge_contexts_exn c1 c2 in
      let regex_definition = RegExOr(r1',r2') in
      let regex_variable =
        RegexContext.autogen_id
          context
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          context
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExStar r' ->
      let (r'',c) = iteratively_deepen r' in
      let regex_definition = RegExStar r'' in
      let regex_variable =
        RegexContext.autogen_id
          c
          regex_definition
      in
      let context =
        RegexContext.insert_exn
          c
          regex_variable
          regex_definition
          false
        in
      (RegExVariable regex_variable,context)
  | RegExVariable _ ->
      (r,RegexContext.empty)
  end

(*let rec ordered_exampled_dnf_regex_to_regex
    (r:ordered_exampled_dnf_regex) : regex =
  dnf_regex_to_regex (ordered_exampled_dnf_regex_to_dnf_regex r)*)

let expand_once
    (rc:RegexContext.t)
    (r1:regex)
    (r2:regex)
  : (regex * regex) list =
  let retrieve_expansions_from_transform (transform:regex -> regex list):
    (regex * regex) list =
    (List.map
       ~f:(fun le -> (le, r2))
       (transform r1))
    @
    (List.map
       ~f:(fun re -> (r1, re))
       (transform r2))
  in
  
  let all_immediate_expansions =
    (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform (expand_userdefs rc))
    @ (retrieve_expansions_from_transform
         (expand_stars empty_or_not_star_expansion_right))
    @ (retrieve_expansions_from_transform
         (expand_stars empty_or_not_star_expansion_left))
  in

  all_immediate_expansions

