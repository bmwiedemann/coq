(************************************************************************)
(*         *   The Coq Proof Assistant / The Coq Development Team       *)
(*  v      *   INRIA, CNRS and contributors - Copyright 1999-2019       *)
(* <O___,, *       (see CREDITS file for the list of authors)           *)
(*   \VV/  **************************************************************)
(*    //   *    This file is distributed under the terms of the         *)
(*         *     GNU Lesser General Public License Version 2.1          *)
(*         *     (see LICENSE file for the text of the license)         *)
(************************************************************************)

let fatal_error exn =
  Topfmt.(in_phase ~phase:ParsingCommandLine print_err_exn exn);
  let exit_code = if (CErrors.is_anomaly exn) then 129 else 1 in
  exit exit_code

let error_wrong_arg msg =
  prerr_endline msg; exit 1

let error_missing_arg s =
  prerr_endline ("Error: extra argument expected after option "^s);
  prerr_endline "See -help for the syntax of supported options";
  exit 1

(******************************************************************************)
(* Imperative effects! This must be fixed at some point.                      *)
(******************************************************************************)
let set_worker_id opt s =
  assert (s <> "master");
  Flags.async_proofs_worker_id := s

let set_type_in_type () =
  let typing_flags = Environ.typing_flags (Global.env ()) in
  Global.set_typing_flags { typing_flags with Declarations.check_universes = false }

let set_no_template_check () =
  let typing_flags = Environ.typing_flags (Global.env ()) in
  Global.set_typing_flags { typing_flags with Declarations.check_template = false }

(******************************************************************************)

type color = [`ON | `AUTO | `EMACS | `OFF]

type native_compiler = NativeOff | NativeOn of { ondemand : bool }

type option_command = OptionSet of string option | OptionUnset

type coqargs_logic_config = {
  impredicative_set : Declarations.set_predicativity;
  indices_matter    : bool;
  toplevel_name     : Stm.interactive_top;
  allow_sprop       : bool;
  cumulative_sprop  : bool;
}

type coqargs_config = {
  logic       : coqargs_logic_config;
  rcfile      : string option;
  coqlib      : string option;
  color       : color;
  enable_VM   : bool;
  native_compiler : native_compiler;
  stm_flags   : Stm.AsyncOpts.stm_opt;
  debug       : bool;
  diffs_set   : bool;
  time        : bool;
  print_emacs : bool;
  set_options : (Goptions.option_name * option_command) list;
}

type coqargs_pre = {
  load_init   : bool;
  load_rcfile : bool;

  ml_includes : Loadpath.coq_path list;
  vo_includes : Loadpath.coq_path list;
  vo_requires : (string * string option * bool option) list;
  (* None = No Import; Some false = Import; Some true = Export *)

  load_vernacular_list : (string * bool) list;

  inputstate  : string option;
}

type coqargs_query =
  | PrintTags | PrintWhere | PrintConfig
  | PrintVersion | PrintMachineReadableVersion
  | PrintHelp of Usage.specific_usage

type coqargs_main =
  | Queries of coqargs_query list
  | Run

type coqargs_post = {
  memory_stat : bool;
  output_context : bool;
}

type t = {
  config : coqargs_config;
  pre : coqargs_pre;
  main : coqargs_main;
  post : coqargs_post;
}

let default_toplevel = Names.(DirPath.make [Id.of_string "Top"])

let default_native =
  if Coq_config.native_compiler
  then NativeOn {ondemand=true}
  else NativeOff

let default_logic_config = {
  impredicative_set = Declarations.PredicativeSet;
  indices_matter = false;
  toplevel_name = Stm.TopLogical default_toplevel;
  allow_sprop = true;
  cumulative_sprop = false;
}

let default_config = {
  logic        = default_logic_config;
  rcfile       = None;
  coqlib       = None;
  color        = `AUTO;
  enable_VM    = true;
  native_compiler = default_native;
  stm_flags    = Stm.AsyncOpts.default_opts;
  debug        = false;
  diffs_set    = false;
  time         = false;
  print_emacs  = false;
  set_options  = [];

  (* Quiet / verbosity options should be here *)
}

let default_pre = {
  load_init    = true;
  load_rcfile  = true;
  ml_includes  = [];
  vo_includes  = [];
  vo_requires  = [];
  load_vernacular_list = [];
  inputstate   = None;
}

let default_queries = []

let default_post = {
  memory_stat  = false;
  output_context = false;
}

let default = {
  config = default_config;
  pre    = default_pre;
  main   = Run;
  post   = default_post;
}

(******************************************************************************)
(* Functional arguments                                                       *)
(******************************************************************************)
let add_ml_include opts s =
  Loadpath.{ opts with pre = { opts.pre with ml_includes = {recursive = false; path_spec = MlPath s} :: opts.pre.ml_includes }}

let add_vo_include opts unix_path coq_path implicit =
  let open Loadpath in
  let coq_path = Libnames.dirpath_of_string coq_path in
  { opts with pre = { opts.pre with vo_includes = {
        recursive = true;
        path_spec = VoPath { unix_path; coq_path; has_ml = AddNoML; implicit } } :: opts.pre.vo_includes }}

let add_vo_require opts d p export =
  { opts with pre = { opts.pre with vo_requires = (d, p, export) :: opts.pre.vo_requires }}

let add_compat_require opts v =
  match v with
  | Flags.V8_9 -> add_vo_require opts "Coq.Compat.Coq89" None (Some false)
  | Flags.V8_10 -> add_vo_require opts "Coq.Compat.Coq810" None (Some false)
  | Flags.V8_11 -> add_vo_require opts "Coq.Compat.Coq811" None (Some false)
  | Flags.Current -> add_vo_require opts "Coq.Compat.Coq812" None (Some false)

let add_load_vernacular opts verb s =
  { opts with pre = { opts.pre with load_vernacular_list = (CUnix.make_suffix s ".v",verb) :: opts.pre.load_vernacular_list }}

(** Options for proof general *)
let set_emacs opts =
  Printer.enable_goal_tags_printing := true;
  { opts with config = { opts.config with color = `EMACS; print_emacs = true }}

let set_logic f oval =
  { oval with config = { oval.config with logic = f oval.config.logic }}

let set_color opts = function
  | "yes" | "on" -> { opts with config = { opts.config with color = `ON }}
  | "no" | "off" -> { opts with config = { opts.config with color = `OFF }}
  | "auto" -> { opts with config = { opts.config with color = `AUTO }}
  | _ ->
    error_wrong_arg ("Error: on/off/auto expected after option color")

let set_query opts q =
  { opts with main = match opts.main with
  | Run -> Queries (default_queries@[q])
  | Queries queries -> Queries (queries@[q])
  }

let warn_deprecated_inputstate =
  CWarnings.create ~name:"deprecated-inputstate" ~category:"deprecated"
         (fun () -> Pp.strbrk "The inputstate option is deprecated and discouraged.")

let warn_deprecated_simple_require =
  CWarnings.create ~name:"deprecated-boot" ~category:"deprecated"
         (fun () -> Pp.strbrk "The -require option is deprecated, please use -require-import instead.")

let set_inputstate opts s =
  warn_deprecated_inputstate ();
  { opts with pre = { opts.pre with inputstate = Some s }}

(******************************************************************************)
(* Parsing helpers                                                            *)
(******************************************************************************)
let get_bool opt = function
  | "yes" | "on" -> true
  | "no" | "off" -> false
  | _ ->
    error_wrong_arg ("Error: yes/no expected after option "^opt)

let get_int opt n =
  try int_of_string n
  with Failure _ ->
    error_wrong_arg ("Error: integer expected after option "^opt)

let get_float opt n =
  try float_of_string n
  with Failure _ ->
    error_wrong_arg ("Error: float expected after option "^opt)

let get_host_port opt s =
  match String.split_on_char ':' s with
  | [host; portr; portw] ->
    Some (Spawned.Socket(host, int_of_string portr, int_of_string portw))
  | ["stdfds"] -> Some Spawned.AnonPipe
  | _ ->
    error_wrong_arg ("Error: host:portr:portw or stdfds expected after option "^opt)

let get_error_resilience opt = function
  | "on" | "all" | "yes" -> `All
  | "off" | "no" -> `None
  | s -> `Only (String.split_on_char ',' s)

let get_priority opt s =
  try CoqworkmgrApi.priority_of_string s
  with Invalid_argument _ ->
    error_wrong_arg ("Error: low/high expected after "^opt)

let get_async_proofs_mode opt = let open Stm.AsyncOpts in function
  | "no" | "off" -> APoff
  | "yes" | "on" -> APon
  | "lazy" -> APonLazy
  | _ ->
    error_wrong_arg ("Error: on/off/lazy expected after "^opt)

let get_cache opt = function
  | "force" -> Some Stm.AsyncOpts.Force
  | _ ->
    error_wrong_arg ("Error: force expected after "^opt)


let get_native_name s =
  (* We ignore even critical errors because this mode has to be super silent *)
  try
    String.concat "/" [Filename.dirname s;
      Nativelib.output_dir; Library.native_name_from_filename s]
  with _ -> ""

let to_opt_key = Str.(split (regexp " +"))

let parse_option_set opt =
  match String.index_opt opt '=' with
  | None -> to_opt_key opt, None
  | Some eqi ->
    let len = String.length opt in
    let v = String.sub opt (eqi+1) (len - eqi - 1) in
    to_opt_key (String.sub opt 0 eqi), Some v

(* Main parsing routine *)
(*s Parsing of the command line *)

let parse_args ~help ~init arglist : t * string list =
  let args = ref arglist in
  let extras = ref [] in
  let rec parse oval = match !args with
  | [] ->
    (oval, List.rev !extras)
  | opt :: rem ->
    args := rem;
    let next () = match !args with
      | x::rem -> args := rem; x
      | [] -> error_missing_arg opt
    in
    let noval = begin match opt with

    (* Complex options with many args *)
    |"-I"|"-include" ->
      begin match rem with
      | d :: rem ->
        args := rem;
        add_ml_include oval d
      | [] -> error_missing_arg opt
      end
    |"-Q" ->
      begin match rem with
      | d :: p :: rem ->
        args := rem;
        add_vo_include oval d p false
      | _ -> error_missing_arg opt
      end
    |"-R" ->
      begin match rem with
      | d :: p :: rem ->
        args := rem;
        add_vo_include oval d p true
      | _ -> error_missing_arg opt
      end

    (* Options with one arg *)
    |"-coqlib" ->
      { oval with config = { oval.config with coqlib = Some (next ())
      }}

    |"-async-proofs" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_mode = get_async_proofs_mode opt (next())
      }}}
    |"-async-proofs-j" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_n_workers = (get_int opt (next ()))
      }}}
    |"-async-proofs-cache" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_cache = get_cache opt (next ())
      }}}

    |"-async-proofs-tac-j" ->
      let j = get_int opt (next ()) in
      if j <= 0 then begin
        error_wrong_arg ("Error: -async-proofs-tac-j only accepts values greater than or equal to 1")
      end;
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_n_tacworkers = j
      }}}

    |"-async-proofs-worker-priority" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_worker_priority = get_priority opt (next ())
      }}}

    |"-async-proofs-private-flags" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_private_flags = Some (next ());
      }}}

    |"-async-proofs-tactic-error-resilience" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_tac_error_resilience = get_error_resilience opt (next ())
      }}}

    |"-async-proofs-command-error-resilience" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_cmd_error_resilience = get_bool opt (next ())
      }}}

    |"-async-proofs-delegation-threshold" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_delegation_threshold = get_float opt (next ())
      }}}

    |"-worker-id" -> set_worker_id opt (next ()); oval

    |"-compat" ->
      let v = G_vernac.parse_compat_version (next ()) in
      Flags.compat_version := v;
      add_compat_require oval v

    |"-exclude-dir" ->
      System.exclude_directory (next ()); oval

    |"-init-file" ->
      { oval with config = { oval.config with rcfile = Some (next ()); }}

    |"-inputstate"|"-is" ->
      set_inputstate oval (next ())

    |"-load-ml-object" ->
      Mltop.dir_ml_load (next ()); oval

    |"-load-ml-source" ->
      Mltop.dir_ml_use (next ()); oval

    |"-load-vernac-object" ->
      add_vo_require oval (next ()) None None

    |"-load-vernac-source"|"-l" ->
      add_load_vernacular oval false (next ())

    |"-load-vernac-source-verbose"|"-lv" ->
      add_load_vernacular oval true (next ())

    |"-mangle-names" ->
      Goptions.set_bool_option_value ["Mangle"; "Names"] true;
      Goptions.set_string_option_value ["Mangle"; "Names"; "Prefix"] (next ());
      oval

    |"-print-mod-uid" ->
      let s = String.concat " " (List.map get_native_name rem) in print_endline s; exit 0

    |"-profile-ltac-cutoff" ->
      Flags.profile_ltac := true;
      Flags.profile_ltac_cutoff := get_float opt (next ());
      oval

    |"-rfrom" ->
      let from = next () in add_vo_require oval (next ()) (Some from) None

    |"-require" ->
      warn_deprecated_simple_require ();
      add_vo_require oval (next ()) None (Some false)

    |"-require-import" | "-ri" -> add_vo_require oval (next ()) None (Some false)

    |"-require-export" | "-re" -> add_vo_require oval (next ()) None (Some true)

    |"-require-import-from" | "-rifrom" ->
      let from = next () in add_vo_require oval (next ()) (Some from) (Some false)

    |"-require-export-from" | "-refrom" ->
      let from = next () in add_vo_require oval (next ()) (Some from) (Some true)

    |"-top" ->
      let topname = Libnames.dirpath_of_string (next ()) in
      if Names.DirPath.is_empty topname then
        CErrors.user_err Pp.(str "Need a non empty toplevel module name");
      { oval with config = { oval.config with logic = { oval.config.logic with toplevel_name = Stm.TopLogical topname }}}

    |"-topfile" ->
      { oval with config = { oval.config with logic = { oval.config.logic with toplevel_name = Stm.TopPhysical (next()) }}}

    |"-main-channel" ->
      Spawned.main_channel := get_host_port opt (next()); oval

    |"-control-channel" ->
      Spawned.control_channel := get_host_port opt (next()); oval

    |"-w" | "-W" ->
      let w = next () in
      if w = "none" then
        (CWarnings.set_flags w; oval)
      else
        let w = CWarnings.get_flags () ^ "," ^ w in
        CWarnings.set_flags (CWarnings.normalize_flags_string w);
        oval

    |"-bytecode-compiler" ->
      { oval with config = { oval.config with enable_VM = get_bool opt (next ()) }}

    |"-native-compiler" ->

      (* We use two boolean flags because the four states make sense, even if
      only three are accessible to the user at the moment. The selection of the
      produced artifact(s) (`.vo`, `.vio`, `.coq-native`, ...) should be done by
      a separate flag, and the "ondemand" value removed. Once this is done, use
      [get_bool] here. *)
      let native_compiler =
        match (next ()) with
        | ("yes" | "on") -> NativeOn {ondemand=false}
        | "ondemand" -> NativeOn {ondemand=true}
        | ("no" | "off") -> NativeOff
        | _ ->
          error_wrong_arg ("Error: (yes|no|ondemand) expected after option -native-compiler")
      in
      { oval with config = { oval.config with native_compiler }}

    | "-set" ->
      let opt = next() in
      let opt, v = parse_option_set opt in
      { oval with config = { oval.config with set_options = (opt, OptionSet v) :: oval.config.set_options }}

    | "-unset" ->
      let opt = next() in
      let opt = to_opt_key opt in
      { oval with config = { oval.config with set_options = (opt, OptionUnset) :: oval.config.set_options }}

    (* Options with zero arg *)
    |"-async-queries-always-delegate"
    |"-async-proofs-always-delegate"
    |"-async-proofs-never-reopen-branch" ->
      { oval with config = { oval.config with stm_flags = { oval.config.stm_flags with
        Stm.AsyncOpts.async_proofs_never_reopen_branch = true
      }}}
    |"-test-mode" -> Vernacinterp.test_mode := true; oval
    |"-beautify" -> Flags.beautify := true; oval
    |"-bt" -> Backtrace.record_backtrace true; oval
    |"-color" -> set_color oval (next ())
    |"-config"|"--config" -> set_query oval PrintConfig
    |"-debug" -> Coqinit.set_debug (); oval
    |"-diffs" -> let opt = next () in
                  if List.exists (fun x -> opt = x) ["off"; "on"; "removed"] then
                    Proof_diffs.write_diffs_option opt
                  else
                    error_wrong_arg "Error: on|off|removed expected after -diffs";
                  { oval with config = { oval.config with diffs_set = true }}
    |"-stm-debug" -> Stm.stm_debug := true; oval
    |"-emacs" -> set_emacs oval
    |"-impredicative-set" ->
      set_logic (fun o -> { o with impredicative_set = Declarations.ImpredicativeSet }) oval
    |"-allow-sprop" -> set_logic (fun o -> { o with allow_sprop = true }) oval
    |"-disallow-sprop" -> set_logic (fun o -> { o with allow_sprop = false }) oval
    |"-sprop-cumulative" -> set_logic (fun o -> { o with cumulative_sprop = true }) oval
    |"-indices-matter" -> set_logic (fun o -> { o with indices_matter = true }) oval
    |"-m"|"--memory" -> { oval with post = { oval.post with memory_stat = true }}
    |"-noinit"|"-nois" -> { oval with pre = { oval.pre with load_init = false }}
    |"-output-context" -> { oval with post = { oval.post with output_context = true }}
    |"-profile-ltac" -> Flags.profile_ltac := true; oval
    |"-q" -> { oval with pre = { oval.pre with load_rcfile = false; }}
    |"-quiet"|"-silent" ->
      Flags.quiet := true;
      Flags.make_warn false;
      oval
    |"-list-tags" -> set_query oval PrintTags
    |"-time" -> { oval with config = { oval.config with time = true }}
    |"-type-in-type" -> set_type_in_type (); oval
    |"-no-template-check" -> set_no_template_check (); oval
    |"-unicode" -> add_vo_require oval "Utf8_core" None (Some false)
    |"-where" -> set_query oval PrintWhere
    |"-h"|"-H"|"-?"|"-help"|"--help" -> set_query oval (PrintHelp help)
    |"-v"|"--version" -> set_query oval PrintVersion
    |"-print-version"|"--print-version" -> set_query oval PrintMachineReadableVersion

    (* Unknown option *)
    | s ->
      extras := s :: !extras;
      oval
    end in
    parse noval
  in
  try
    parse init
  with any -> fatal_error any

(* We need to reverse a few lists *)
let parse_args ~help ~init args =
  let opts, extra = parse_args ~help ~init args in
  let opts =
    { opts with
      pre = { opts.pre with
              ml_includes = List.rev opts.pre.ml_includes
            ; vo_includes = List.rev opts.pre.vo_includes
            ; vo_requires = List.rev opts.pre.vo_requires
            ; load_vernacular_list = List.rev opts.pre.load_vernacular_list
            }
    ; config = { opts.config with
                 set_options = List.rev opts.config.set_options
               } ;
    } in
  opts, extra

(******************************************************************************)
(* Startup LoadPath and Modules                                               *)
(******************************************************************************)
(* prelude_data == From Coq Require Import Prelude. *)
let prelude_data = "Prelude", Some "Coq", Some false

let require_libs opts =
  if opts.pre.load_init then prelude_data :: opts.pre.vo_requires else opts.pre.vo_requires

let cmdline_load_path opts =
  opts.pre.ml_includes @ opts.pre.vo_includes

let build_load_path opts =
  Coqinit.libs_init_load_path ~load_init:opts.pre.load_init @
  cmdline_load_path opts
