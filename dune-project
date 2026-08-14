(lang dune 3.18)

(name sandwalk)

(version 0.4.0)

(generate_opam_files true)

(source
 (github s-kostyaev/sandwalk))

(authors "Sergey Kostyaev")

(maintainers "Sergey Kostyaev <sskostyaev@gmail.com>")

(license MIT)

(package
 (name sandwalk)
 (synopsis "Deterministic research orchestration for AI agents")
 (description
  "Sandwalk coordinates research workflows, records source provenance, and validates evidence without invoking an LLM.")
 (depends
  (ocaml (>= 5.2))
  (dune (>= 3.18))
  core
  core_unix
  async
  async_unix
  yojson
  sqlite3
  ppx_jane
  (ppx_expect :with-test)))
