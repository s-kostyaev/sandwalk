let check database return_code =
  if not (Sqlite3.Rc.is_success return_code)
  then failwith (Sqlite3.errmsg database)
;;

let print_query database sql =
  check
    database
    (Sqlite3.exec database sql ~cb:(fun row _headers ->
       row
       |> Array.to_list
       |> List.map (Option.value ~default:"NULL")
       |> String.concat "|"
       |> print_endline))
;;

let () =
  let database = Sqlite3.db_open Sys.argv.(1) in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.db_close database : bool))
    (fun () ->
      print_query database "SELECT slug, phase FROM workspaces";
      print_query database "PRAGMA user_version";
      print_query database "PRAGMA journal_mode";
      print_query database "PRAGMA integrity_check")
;;
