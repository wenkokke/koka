/*-----------------------------------------------------------------------------
Copyright 2020-2021, Microsoft Research, Daan Leijen.
This is free software; you can redistribute it and/or modify it under the
terms of the Apache License, Version 2.0. A copy of the License can be
found in the LICENSE file at the root of this distribution.

Run this to create an install 'bundle' as a .tar file.
-----------------------------------------------------------------------------*/
import std/os/path
import std/os/dir
import std/os/process
import std/os/env
import std/os/flags

val header = "usage:\n stack exec koka -- util/bundle [-- [options]]\n\noptions:"

struct iflags {
  prefixdir : string = ""
  postfixtag: string = ""
  minimal   : bool   = False
  dist      : bool   = True
  sysghc    : bool   = False
  exe       : string = ""
}

val flag-descs : list<flag<iflags>> = {
  fun set-prefix( f : iflags, s : string ) : iflags { f(prefixdir = s) }
  fun set-postfix( f : iflags, s : string ) : iflags { f(postfixtag = s) }
  fun set-minimal( f : iflags, b : bool ) : iflags  { f(minimal = b) }
  fun set-install( f : iflags, b : bool ) : iflags  { f(dist = !b) }
  fun set-sysghc( f : iflags, b : bool ) : iflags  { f(sysghc = b) }
  fun set-exe( f : iflags, s : string ) : iflags { f(exe = s) }
  [ Flag( "m", ["minimal"], Bool(set-minimal), "use minimal install (more quick)" ),
    Flag( "i", ["install"], Bool(set-install), "install directly without creating a distribution bundle"),
    Flag( "", ["prefix"], Req(set-prefix,"DIR"), "set prefix directory for install ('~/.local')" ),
    Flag( "", ["postfix"], Req(set-postfix,"POST"), "set postfix instead of <version>-<os>-<arch>"),
    Flag( "", ["koka"], Req(set-exe,"EXE"), "set koka executable path; use 'stack' or 'cabal' for a local build"),
    Flag( "", ["system-ghc"], Bool(set-sysghc), "use system-ghc if building with 'stack'")
  ]
}

public fun process-flags() : <ndet,console> maybe<iflags> {
  val (flags,args,errs) = parse( Iflags(), flag-descs, get-args() )
  if (errs.is-nil && args.is-nil) then {
    Just(flags)
  }
  else {
    println( errs.join("\n") ++ "\n" ++ flag-descs.usage(header) )
    Nothing
  }
}

fun main() {
  if (!is-directory("kklib".path)) then {
    println("you can only run 'util/bundle' from the koka root directory")
    println(flag-descs.usage(header))
    return ()
  }
  match (process-flags()) {
    Nothing -> ()
    Just(flags) -> {
      val version = "v" ++ get-compiler-version()
      val cc      = get-cc-name()
      val (koka-exe, koka-run) = koka-exe-path(flags.exe, flags.sysghc)
      val post   = flags.postfixtag || get-default-postfix()
      val predir = if (flags.prefixdir.is-empty)
                    then get-default-prefix(flags.dist, post)
                    else flags.prefixdir.path
      bundle( predir, cc, version, flags.dist, post, flags.minimal, koka-exe, koka-run )      
    }
  }
}

fun bundle( prefixdir : path, cc : string, version : string, dist : bool, post : string, 
            minimal : bool, koka-exe : path, koka-run : string ) 
{
  // Install paths  
  val bindir  = prefixdir / "bin"
  val libdir  = prefixdir / "lib" / "koka" / version
  val sharedir= prefixdir / "share" / "koka" / version
  val tarname = (prefixdir / ".." / ("koka-" ++ post ++ ".tar.gz")).string  

  if (dist) then {
    println("creating koka distribution bundle:")
    println("  bundle : " ++ tarname)
    println("  cc     : " ++ cc ++ (if (cc=="clang-cl") then ", cl" else ""))
  }
  else {
    println("installing koka:" )
    println("  bin    : " ++ bindir.string)
    println("  lib    : " ++ libdir.string)
    println("  share  : " ++ sharedir.string)
    println("  cc     : " ++ cc)
  }
  println("  exe    : " ++ koka-exe.string)
  println("  version: " ++ version)
  ensure-dir(bindir)
  ensure-dir(libdir)
  ensure-dir(sharedir)

  // Build kklib versions
  [Debug,DRelease,Release].foreach fn(v){ 
    build-libraries( cc,v,version,dist,minimal,koka-run ) 
  }

  // Copy Koka
  println("copy koka executable...")
  copy-file-to-dir(koka-exe, bindir)

  // Copy std libs
  val stdlibdir = sharedir / "lib"
  println("copy standard libraries...")
  copy-directory("lib/std".path, stdlibdir / "std")
  copy-file-to-dir("lib/toc.kk".path, stdlibdir)
  copy-file-to-dir("lib/package.std.json".path, stdlibdir)

  // Copy samples
  println("copy samples...")
  copy-directory("samples".path, stdlibdir / "samples")

  // Copy kklib
  val kklibdir = sharedir / "kklib"
  println("copy kklib runtime...")
  copy-directory("kklib/src".path, kklibdir / "src")
  copy-directory("kklib/include".path, kklibdir / "include")
  copy-directory("kklib/mimalloc".path, kklibdir / "mimalloc")
  copy-file-to-dir("kklib/CMakeLists.txt".path, kklibdir)
  // copy-file-to-dir("kklib/kkmain.cmake".path, kklibdir)

  // Copy contrib
  val contribdir = sharedir / "contrib"
  println("copy contrib...")
  ensure-dir(contribdir)
  copy-file-to-dir("contrib/biginteger.js".path, contribdir)
  copy-directory("support/atom".path, contribdir / "atom")
  copy-directory("support/vscode".path, contribdir / "vscode")  
  copy-directory("support/emacs".path, contribdir / "emacs")  

  // Copy kklib binaries
  [Debug,DRelease,Release].foreach fn(v){
    println("copying standard library: " ++ v.show)
    copy-libraries(libdir, cc, v, version)
    if (dist && cc=="clang-cl") then {
      copy-libraries(libdir, "cl", v, version)
    }
  }

  if (dist) then {
    // tar the result
    val tarcmd = ["tar -czf",tarname,"-C",prefixdir.show,"bin","lib","share"].join(" ")
    println("> " ++ tarcmd)
    run-system(tarcmd)
    ()
  }

  if (dist) then {
    println("distribution bundle created.")
    println("  bundle : " ++ tarname)
    println("  cc     : " ++ cc ++ (if (cc=="clang-cl") then ", cl" else ""))
  }
  else {
    println("done installing.")
    println("  bin    : " ++ bindir.string)
    println("  lib    : " ++ libdir.string)
    println("  share  : " ++ sharedir.string)
    println("  cc     : " ++ cc)
  }
  println("  version: " ++ version)
}

fun koka-exe-path(exe-opt : string, sysghc : bool) : io (path,string) {
  val exe      = if (!exe-opt.is-empty) then exe-opt 
                 elif (get-env("STACK_EXE").default("").is-empty) then "cabal" 
                 else "stack"  
  val koka-run = if (exe == "stack") then "stack exec koka " ++ (if sysghc then "--system-ghc --skip-ghc-check " else "") ++ "--"
                 elif (exe == "cabal") then "cabal new-run koka --"
                 else exe
  val info     = run-system-read(koka-run ++ " --version").exn
  val bin      = info.lines.filter(fn(s){ s.starts-with("bin ").bool }).head.unjust
  val fpath    = bin.find(": ").unjust.after.string.trim / "koka"  
  val koka-exe = if (fpath.is-file) then fpath else fpath.change-ext(".exe")
  if (!koka-exe.is-file) then throw("unable to find koka executable: use '> stack build' first.\n  (" ++ koka-exe.string ++ ")")
  (koka-exe, koka-run)
}

fun get-default-prefix(dist : bool, post : string) : io path {
  if (dist) then {
    "bundle" / ("local-" ++ post)
  }
  else {
    homedir() / ".local"
  }
}

fun get-default-postfix() : io string {
  val ver     = get-compiler-version()
  val arch0   = get-cpu-arch()
  val arch    = if (ver <= "2.1.6" && arch0 == "x64") then "amd64" else arch0
  val osname0 = get-os-name()
  val osname  = if (ver <= "2.1.8" && osname0 == "macos") then "osx" else osname0
  ["v" ++ ver, osname, arch].join("-")
}

fun get-build-dir(cc : string, variant : variant, version : string ) : path {
  "out".path / (version ++ "-bundle") / (cc ++ "-" ++ variant.show)
}



type variant {
  Debug
  DRelease
  Release
}

fun show( v : variant ) : string {
  match(v) {
    Debug    -> "debug"
    DRelease -> "drelease"
    Release  -> "release"
  }
}

fun copy-libraries( libdir : path, cc : string, variant : variant, version : string ) : io () {
  val builddir = get-build-dir( cc, variant, version )
  val vardir = builddir.basename
  val objdir = libdir / vardir
  val kklib  = if (get-os-name()=="windows") then "kklib.obj" else "kklib.o"
  ensure-dir(objdir)
  copy-file-to-dir( builddir / kklib, objdir )
  val all = list-directory(builddir)
  val files = all.filter(fn(f){ !is-directory(f) })
  val objs = files.filter(fn(f){ 
    val ext = f.extname
    ((f.basename.starts-with("std_").bool && ext != "core") || ext == "a" || ext == "lib" )
  })
  objs.foreach fn(obj){
    // println("copy " ++ obj.string)
    copy-file-to-dir( obj, objdir )
  }
}

fun build-libraries(cc : string, variant : variant, version : string, dist : bool, minimal : bool, koka-run : string) : io () {
  println("build standard libraries: " ++ variant.show ++ "...")
  val extra = match(variant) {
    Debug    -> ""
    DRelease -> "-O2"
    Release  -> "-O2 --no-debug"
  }
  val prog = if (minimal) then "util/link-min" else "util/link-std"
  val builddir = get-build-dir( cc, variant, version )
  val args = "--cc=" ++ cc ++ " " ++ extra
  val cmd  = [koka-run, "--cc=" ++ cc, "--builddir=" ++ builddir.show, extra, prog].join(" ")
  println("> "  ++ cmd)
  val code = run-system( cmd )
  if (code != 0) then throw("error: " ++ code.show)

  if (dist && cc=="clang-cl") then {
    // also generate cl binaries on windows
    val clbuilddir = get-build-dir("cl", variant, version)
    val clcmd  = [koka-run, "--cc=cl", "--builddir=" ++ clbuilddir.show, extra, prog].join(" ")
    println("> "  ++ clcmd)
    run-system( clcmd )
    ()
  }
}
