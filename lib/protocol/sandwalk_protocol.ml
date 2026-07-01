open! Core

module Error = struct
  type t =
    { code : string
    ; message : string
    }
end

module Envelope = struct
  type t =
    { ok : bool
    ; result : Yojson.Safe.t option
    ; error : Error.t option
    ; next : string option
    }

  let success ?next ~result () = { ok = true; result = Some result; error = None; next }

  let failure ?next ~code ~message () =
    { ok = false; result = None; error = Some { Error.code; message }; next }
  ;;

  let to_yojson { ok; result; error; next } =
    let fields = [ "ok", `Bool ok ] in
    let fields =
      match result with
      | None -> fields
      | Some value -> fields @ [ "result", value ]
    in
    let fields =
      match error with
      | None -> fields
      | Some { Error.code; message } ->
        fields
        @ [ "error", `Assoc [ "code", `String code; "message", `String message ] ]
    in
    let fields =
      match next with
      | None -> fields
      | Some command -> fields @ [ "next", `String command ]
    in
    `Assoc fields
  ;;

  let render t = t |> to_yojson |> Yojson.Safe.to_string
end

let%expect_test "renders a compact failure with one next command" =
  Envelope.failure
    ~code:"PLAN_NOT_VALIDATED"
    ~message:"Plan must be validated before sealing."
    ~next:"sandwalk plan validate --slug 'typed-harness'"
    ()
  |> Envelope.render
  |> print_endline;
  [%expect
    {| {"ok":false,"error":{"code":"PLAN_NOT_VALIDATED","message":"Plan must be validated before sealing."},"next":"sandwalk plan validate --slug 'typed-harness'"} |}]
;;
