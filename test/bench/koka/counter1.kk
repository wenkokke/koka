import std/num/int32

effect val ask : int

linear effect st {
  fun get() : int32
  fun set(i : int32)  : ()
}

fun state( i : int32, action : () -> <st|e> a ) : e a {
  var s := i
  with {
    fun get(){ s }
    fun set(x){ s := x }    
  } 
  action()
}

fun reader( init : int, action ) {
  println("enter reader " ++ init.show)
  with finally{ println("leave reader " ++ init.show) }
  with val ask = init
  action()
}

fun counter( c : int32 ) : _ int {
  val i = get()
  if (i==zero) then c.int else {
    set(i.dec)
    counter(c.inc)
  }
}

fun main() {
  with state(100100100.int32)
  with reader(0)
  counter(zero).println
}