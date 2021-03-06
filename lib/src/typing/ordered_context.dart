// Copyright (c) 2018, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import '../ast/ast.dart'
    show
        Declaration,
        Datatype,
        Identifiable,
        Skolem,
        TypeVariable,
        Quantifier,
        ReduceDatatype,
        TransformDatatype;
import '../ast/monoids.dart' show Monoid, LAndMonoid;
import '../fp.dart' show Pair;
import '../immutable_collections.dart' show ImmutableList;

class DatatypeVerifier extends ReduceDatatype<bool> {
  Monoid<bool> get m => LAndMonoid();
  final Set<int> scope;
  DatatypeVerifier(this.scope);

  bool verify(Datatype type) {
    return type.accept<bool>(this);
  }

  bool visitTypeVariable(TypeVariable typeVariable) {
    return scope.contains(typeVariable.ident);
  }

  bool visitSkolem(Skolem skolem) {
    if (skolem.painted) {
      return false;
    }

    skolem.paint();
    bool checkSolution = m.empty;
    if (skolem.isSolved) {
      checkSolution = skolem.type.accept<bool>(this);
    }

    bool inScope =
        scope.contains(skolem.ident) || scope.contains(-skolem.ident);
    skolem.reset();
    return inScope && checkSolution;
  }
}

abstract class ScopedEntry {
  ScopedEntry predecessor;
  ScopedEntry successor;

  int get ident;

  void insertBefore(ScopedEntry entry) {
    // entry' = pred(entry)
    ScopedEntry entry0 = entry.predecessor;

    // succ(this) = entry
    this.successor = entry;
    // pred(entry) = this
    entry.predecessor = this;
    // succ(entry0) = this
    if (entry0 != null) {
      entry0.successor = this;
    }
    // pred(this) = entry'
    this.predecessor = entry0;
  }

  void insertAfter(ScopedEntry entry) {
    // entry' = succ(entry)
    // print("${entry.successor} = succ($entry)");
    ScopedEntry entry0 = entry.successor;

    // pred(this) = entry
    // print("pred($this) = $entry");
    this.predecessor = entry;
    // succ(entry) = this
    // print("succ($entry) = $this");
    entry.successor = this;
    // pred(entry') = this
    // print("pred($entry0) = $this");
    if (entry0 != null) {
      entry0.predecessor = this;
    }
    // succ(this) = entry0
    // print("succ($this) = $entry0");
    this.successor = entry0;
  }

  // Detaches [this] and the subsequent entries from [predecessor].
  void detach() {
    // entry' = pred(this)
    ScopedEntry entry0 = this.predecessor;
    // succ(entry') = null
    if (entry0 != null) {
      entry0.successor = null;
    }
    // pred(this) = null
    this.predecessor = null;
  }

  bool verify(Set<int> scope) => !scope.contains(ident);
}

class Marker extends ScopedEntry {
  final Skolem skolem;
  Marker(this.skolem);

  int get ident => -skolem.ident;

  String toString() {
    return ">$skolem";
  }
}

class Ascription extends ScopedEntry {
  Declaration decl;
  Datatype type;
  int get ident => decl.ident;
  Ascription(this.decl, this.type);

  String toString() {
    return "$decl : $type";
  }

  bool verify(Set<int> scope) {
    return !scope.contains(ident) && DatatypeVerifier(scope).verify(type);
  }
}

class QuantifiedVariable extends ScopedEntry {
  Quantifier quantifier;
  int get ident => quantifier.ident;
  QuantifiedVariable(this.quantifier);

  String toString() {
    return quantifier.toString();
  }
}

// class MetaExistential extends ScopedEntry {
//   final Existential existential;
//   final Quantifier quantifier;

//   int get ident => quantifier.ident;

//   MetaExistential(this.quantifier, this.existential);

//   String toString() {
//     return "$quantifier := ?${existential.skolem.ident}";
//   }
// }

class Existential extends ScopedEntry {
  final Skolem skolem;
  Datatype get solution => skolem.type;
  // Datatype get solution => skolem.type;
  Existential(this.skolem, [Datatype solution]) {
    // if (solution != null) {
    //   skolem.solve(solution);
    // }
    //this.solution = solution;
  }

  int get ident => skolem.ident;
  bool get isSolved => skolem.isSolved;
  // void solve(Datatype solution) => skolem.solve(solution);
  Existential solve(Datatype solution) {
    skolem.solve(solution);
    return Existential(skolem, solution);
  }
  void equate(Existential ex) => skolem.equate(ex.skolem);

  String toString() {
    if (isSolved) {
      return "?${skolem.ident} = $solution";
    } else {
      return "$skolem";
    }
  }

  bool verify(Set<int> scope) {
    if (!scope.contains(ident)) {
      bool checkSolution =
          isSolved ? DatatypeVerifier(scope).verify(solution) : true;
      return checkSolution;
    } else {
      return false;
    }
  }
}

abstract class OrderedContext2 {
  // Returns the number of elements present in the context.
  int get size;

  factory OrderedContext2.empty() = ListOrderedContext2.empty;

  // Inserts [a] at the rear of the ordering.
  OrderedContext2 insertLast(Identifiable a);

  // Inserts [a] before [successor] in the context.
  OrderedContext2 insertBefore(Identifiable a, Identifiable successor);

  // Solves the existential [skolem] using [solution].
  OrderedContext2 solve(Skolem skolem, Datatype solution);

  // Returns the solution for [skolem]. Returns null if [skolem] is unsolved.
  Datatype solution(Skolem skolem);

  // Drops everything after and including [ident].
  OrderedContext2 drop(Identifiable ident);

  // Installs a marker before [a].
  Pair<Identifiable, OrderedContext2> mark(Identifiable a);

  // Returns true if [a] precedes [b].
  bool precedes(Identifiable a, Identifiable b);

  // Returns true if [a] is present in [this] context, otherwise false.
  bool contains(Identifiable a);

  // Verifies that the context is well-formed.
  bool verify();

  // Applies [this] context as a substitution on [type].
  Datatype apply(Datatype type);
}

class _Entry {
  final Identifiable item;
  int get ident => item.ident;
  _Entry(this.item);

  String toString() => item.toString();
}

class _SolvableEntry extends _Entry {
  final Datatype type;

  _SolvableEntry(Skolem skolem, [this.type = null]) : super(skolem);

  String toString() {
    if (type != null) {
      return "$item = $type";
    } else {
      return super.toString();
    }
  }
}

class _Marker implements Identifiable {
  final Identifiable _item;
  int get ident => -_item.ident;
  _Marker(this._item);

  String toString() => ">$_item";
}

// Naïve implementation. This implementation is intended as a "reference
// implementation".
class ListOrderedContext2 extends TransformDatatype implements OrderedContext2 {
  final ImmutableList<_Entry> _entries;
  ListOrderedContext2.empty() : this._(ImmutableList<_Entry>.empty());
  ListOrderedContext2._(this._entries);

  int get size => _entries.length;

  OrderedContext2 insertLast(Identifiable a) {
    _Entry entry = a is Skolem ? _SolvableEntry(a) : _Entry(a);
    return ListOrderedContext2._(_entries.reverse().cons(entry).reverse());
  }

  OrderedContext2 insertBefore(Identifiable a, Identifiable successor) {
    _Entry entry = a is Skolem ? _SolvableEntry(a) : _Entry(a);
    ImmutableList<_Entry> entries0 = ImmutableList<_Entry>.empty();
    ImmutableList<_Entry> entries = _entries;
    while (!entries.isEmpty) {
      if (entries.head.ident == successor.ident) {
        entries = entries.cons(entry);
        entries = entries0.reverse().concat(entries);
        break;
      } else {
        entries0 = entries0.cons(entries.head);
        entries = entries.tail;
      }
    }

    if (entries.isEmpty) {
      throw "$successor is not present.";
    }
    return ListOrderedContext2._(entries0.reverse().concat(entries));
  }

  OrderedContext2 solve(Skolem skolem, Datatype solution) {
    ImmutableList<_Entry> entries = _entries;
    ImmutableList<_Entry> entries0 = ImmutableList<_Entry>.empty();
    while (!entries.isEmpty) {
      if (entries.head.ident == skolem.ident) {
        entries = entries.tail.cons(_SolvableEntry(skolem, solution));
        break;
      }
      entries0 = entries0.cons(entries.head);
      entries = entries.tail;
    }
    return ListOrderedContext2._(entries0.reverse().concat(entries));
  }

  Datatype solution(Skolem skolem) {
    ImmutableList<_Entry> entries = _entries;
    _Entry entry;
    while (!entries.isEmpty) {
      if (entries.head.ident == skolem.ident) {
        entry = entries.head;
        break;
      } else {
        entries = entries.tail;
      }
    }
    return entry is _SolvableEntry ? entry.type : null;
  }

  OrderedContext2 drop(Identifiable a) {
    ImmutableList<_Entry> entries = _entries;
    ImmutableList<_Entry> entries0 = ImmutableList<_Entry>.empty();
    _Entry entry;
    while (!entries.isEmpty) {
      if (entries.head.ident == a.ident) {
        break;
      }
      entries0 = entries0.cons(entries.head);
      entries = entries.tail;
    }
    return ListOrderedContext2._(entries0.reverse());
  }

  bool precedes(Identifiable a, Identifiable b) {
    ImmutableList<_Entry> sublist = _entries;
    while (!sublist.isEmpty) {
      if (sublist.head.ident == a.ident) break;
      sublist = sublist.tail;
    }

    while (!sublist.isEmpty) {
      if (sublist.head.ident == b.ident) return true;
      sublist = sublist.tail;
    }
    return false;
  }

  bool contains(Identifiable a) {
    ImmutableList<_Entry> entries = _entries;
    while (!entries.isEmpty) {
      if (entries.head.ident == a.ident) return true;
      entries = entries.tail;
    }
    return false;
  }

  Pair<Identifiable, OrderedContext2> mark(Identifiable a) {
    Identifiable marker = _Marker(a);
    return Pair<Identifiable, OrderedContext2>(marker, insertBefore(marker, a));
  }

  bool verify() => false;

  _Entry _lookup(Identifiable a) {
    ImmutableList<_Entry> entries = _entries;
    while (!entries.isEmpty) {
      if (entries.head.ident == a.ident) return entries.head;
      entries = entries.tail;
    }
    return null;
  }

  Datatype apply(Datatype type) {
    return type.accept<Datatype>(this);
  }

  Datatype visitSkolem(Skolem skolem) {
    if (skolem.painted) return skolem;

    _Entry entry = _lookup(skolem);
    if (entry == null) {
      return skolem;
    }

    skolem.paint();
    if (entry is _SolvableEntry) {
      _SolvableEntry ex = entry;
      Datatype result;
      if (ex.type != null) {
        result = ex.type.accept<Datatype>(this);
      } else {
        result = skolem;
      }
      skolem.reset();
      return result;
    } else {
      throw "Logical error: _Entry instance for Skolem $skolem is not an instance of _SolvableEntry.";
    }
  }

  String toString() {
    if (_entries.isEmpty) {
      return "{}";
    }

    // Roll back to the first entry.
    ImmutableList<_Entry> entries = _entries;

    // Build the string
    StringBuffer buf = new StringBuffer();
    buf.write("{");
    while (!entries.isEmpty) {
      _Entry entry = entries.head;
      buf.write(entry.toString());
      entries = entries.tail;
      if (!entries.isEmpty) {
        buf.write(", ");
      }
    }
    buf.write("}");
    return buf.toString();
  }
}

// class MapOrderedContext extends OrderedContext2 {
//   final ImmutableMap<int, Identifiable> entries;
//   int get size => entries.length;
// }

abstract class OrderedContext extends TransformDatatype {
  int get size;
  ScopedEntry get first;

  OrderedContext._();
  factory OrderedContext.empty() = ListOrderedContext.empty;

  OrderedContext insertLast(ScopedEntry entry);
  OrderedContext insertBefore(ScopedEntry entry, ScopedEntry successor);
  OrderedContext update(ScopedEntry entry);
  ScopedEntry lookup(int identifier);
  ScopedEntry lookupAfter(int identifier, ScopedEntry entry);
  OrderedContext drop(ScopedEntry entry);
  bool verify();

  Datatype apply(Datatype type);
}

class ListOrderedContext extends OrderedContext {
  final ImmutableList<ScopedEntry> _entries;
  int get size => _entries.length;
  ScopedEntry get first => _entries.head;

  ListOrderedContext.empty()
      : this._entries = ImmutableList<ScopedEntry>.empty(),
        super._();
  ListOrderedContext._(this._entries) : super._();

  OrderedContext insertLast(ScopedEntry entry) {
    ImmutableList<ScopedEntry> entries;
    entries = _entries.reverse().cons(entry).reverse();
    return ListOrderedContext._(entries);
  }

  OrderedContext insertBefore(ScopedEntry entry, ScopedEntry successor) {
    ImmutableList<ScopedEntry> entries0 = ImmutableList<ScopedEntry>.empty();
    ImmutableList<ScopedEntry> entries = _entries;
    while (!entries.isEmpty) {
      if (entries.head.ident == successor.ident) {
        entries = entries.cons(entry);
        entries = entries0.reverse().concat(entries);
        break;
      } else {
        entries0 = entries0.cons(entries.head);
        entries = entries.tail;
      }
    }
    return ListOrderedContext._(entries);
  }

  ScopedEntry lookup(int identifier) {
    ImmutableList<ScopedEntry> entries = _entries;
    ScopedEntry entry;
    while (!entries.isEmpty) {
      ScopedEntry entry0 = entries.head;
      if (entry0.ident == identifier) {
        entry = entry0;
        break;
      }
      entries = entries.tail;
    }

    return entry;
  }

  ScopedEntry lookupAfter(int identifier, ScopedEntry entry) {
    ImmutableList<ScopedEntry> entries = _entries;
    while (!entries.isEmpty) {
      ScopedEntry entry0 = entries.head;
      entries = entries.tail;
      if (entry0.ident == entry.ident) {
        break;
      }
    }

    ScopedEntry x;
    while (!entries.isEmpty) {
      ScopedEntry entry0 = entries.head;
      if (entry0.ident == identifier) {
        x = entry0;
        break;
      }
      entries = entries.tail;
    }

    return x;
  }

  OrderedContext update(ScopedEntry entry) {
    ImmutableList<ScopedEntry> entries0 = ImmutableList<ScopedEntry>.empty();
    ImmutableList<ScopedEntry> entries = _entries;
    while (!entries.isEmpty) {
      if (entries.head.ident == entry.ident) {
        entries = entries.tail.cons(entry);
        entries = entries0.reverse().concat(entries);
        break;
      } else {
        entries0 = entries0.cons(entries.head);
        entries = entries.tail;
      }
    }
    return ListOrderedContext._(entries);
  }

  OrderedContext drop(ScopedEntry entry) {
    ImmutableList<ScopedEntry> entries = _entries;
    ImmutableList<ScopedEntry> entries0 = ImmutableList<ScopedEntry>.empty();
    while (!entries.isEmpty) {
      ScopedEntry entry0 = entries.head;
      entries = entries.tail;
      if (entry0.ident == entry.ident) {
        break;
      }
      entries0 = entries0.cons(entry0);
    }

    return ListOrderedContext._(entries0.reverse());
  }

  bool verify() => false;

  Datatype apply(Datatype type) {
    return type.accept<Datatype>(this);
  }

  Datatype visitSkolem(Skolem skolem) {
    if (skolem.painted) return skolem;

    ScopedEntry entry = lookup(skolem.ident);
    if (entry == null) {
      return skolem;
    }

    skolem.paint();
    if (entry is Existential) {
      Existential ex = entry;
      Datatype result;
      if (ex.isSolved) {
        result = ex.solution.accept<Datatype>(this);
      } else {
        result = skolem;
      }
      skolem.reset();
      return result;
    } else {
      throw "Logical error: ScopedEntry instance for Skolem $skolem is not an instance of Existential.";
    }
  }

  String toString() {
    if (_entries.isEmpty) {
      return "{}";
    }

    // Roll back to the first entry.
    ImmutableList<ScopedEntry> entries = _entries;

    // Build the string
    StringBuffer buf = new StringBuffer();
    buf.write("{");
    while (!entries.isEmpty) {
      ScopedEntry entry = entries.head;
      buf.write(entry.toString());
      entries = entries.tail;
      if (!entries.isEmpty) {
        buf.write(", ");
      }
    }
    buf.write("}");
    return buf.toString();
  }
}

class MutableOrderedContext extends OrderedContext {
  ScopedEntry _last;
  Map<int, ScopedEntry> _table;

  int get size => _table.length;

  ScopedEntry get first {
    if (_last == null) return null;

    // Roll back.
    ScopedEntry entry = _last;
    while (entry.predecessor != null) {
      entry = entry.predecessor;
    }
    return entry;
  }

  MutableOrderedContext.empty()
      : _last = null,
        _table = new Map<int, ScopedEntry>(),
        super._();

  OrderedContext insertLast(ScopedEntry entry) {
    if (_last == null) {
      _last = entry;
    } else {
      entry.insertAfter(_last);
      _last = entry;
    }

    _table[entry.ident] = entry;
    return this;
  }

  OrderedContext insertBefore(ScopedEntry entry, ScopedEntry successor) {
    assert(entry != _last);
    if (entry == _last) {
      // I think moving the [_last] entry should be an error.
      _last = successor;
    }
    entry.insertBefore(successor);
    _table[entry.ident] = entry;
    return this;
  }

  OrderedContext update(ScopedEntry entry) {
    return null;
  }

  ScopedEntry lookup(int identifier) {
    ScopedEntry entry = _table[identifier];
    assert(entry != null);
    return entry;
  }

  // TODO there might be a clever way to lower the asympotic complexity of this
  // operation.
  ScopedEntry lookupAfter(int identifier, ScopedEntry entry) {
    while (entry != null) {
      if (entry.ident == identifier) break;
      entry = entry.successor;
    }
    return entry;
  }

  // Drops [entry] and everything succeeding it from the context.
  OrderedContext drop(ScopedEntry entry) {
    ScopedEntry parent = entry;
    assert(_table[parent.ident] != null);
    _last = entry.predecessor;
    entry.detach();
    while (entry != null) {
      _table.remove(entry.ident);
      entry = entry.successor;
    }
    assert(_table[parent.ident] == null);
    return this;
  }

  // Verifies whether the context is well-founded.
  bool verify() {
    ScopedEntry entry = first;
    Set<int> scope = new Set<int>();
    while (entry != null) {
      if (entry.verify(scope)) {
        scope.add(entry.ident);
        entry = entry.successor;
      } else {
        return false;
      }
    }
    return true;
  }

  // Apply this context as a substitution.
  Datatype apply(Datatype type) {
    return type.accept<Datatype>(this);
  }

  Datatype visitSkolem(Skolem skolem) {
    if (skolem.painted) return skolem;

    ScopedEntry entry = lookup(skolem.ident);
    if (entry == null) {
      return skolem;
    }

    skolem.paint();
    if (entry is Existential) {
      Existential ex = entry;
      Datatype result;
      if (ex.isSolved) {
        result = ex.solution.accept(this);
      } else {
        result = skolem;
      }
      skolem.reset();
      return result;
    } else {
      throw "Logical error: ScopedEntry instance for Skolem $skolem is not an instance of Existential.";
    }
  }

  // Datatype visitTypeVariable(TypeVariable typeVariable) {
  //   ScopedEntry entry = lookup(typeVariable.ident);
  //   if (entry == null) return typeVariable;

  //   if (entry is QuantifiedVariable) {
  //     // No-op.
  //   } else if (entry is TypeAscription) {
  //     TypeAscription ascription = entry;

  //   } else {
  //     throw "Logical error: ScopedEntry instance for TypeVariable $typeVariable is not an instance of either QuantifiedVariable or TypeAscription.";
  //   }
  // }-

  String toString() {
    if (_last == null) {
      return "{}";
    }

    // Roll back to the first entry.
    ScopedEntry entry = first;

    // Build the string
    StringBuffer buf = new StringBuffer();
    buf.write("{");
    while (entry.successor != null) {
      buf.write(entry.toString());
      buf.write(", ");
      entry = entry.successor;
    }
    buf.write(entry.toString());
    buf.write("}");
    return buf.toString();
  }
}

// class Marker2 {
//   final int ident;
//   Marker2._(this.ident);
// }

// abstract class OrderedContext2 {
//   factory OrderedContext2.empty() = _MapBasedContext.empty;

//   OrderedContext2 add(Skolem skolem);
//   OrderedContext2 drop(Skolem skolem);

//   Pair<Marker2, OrderedContext2> mark({Skolem successor});
//   OrderedContext2 unmark(Marker2 marker);

//   OrderedContext2 solve(Skolem skolem, Datatype solution);
// }

// abstract class _MapBasedContext implements OrderedContext2 {
//   final ImmutableMap<int, ScopedEntry> _entries;
//   final ImmutableMap<int, List<int>> _orderings;
//   _MapBasedContext.empty()
//       : _entries = ImmutableMap<int, ScopedEntry>.empty(),
//         _orderings = ImmutableMap<int, List<int>>.empty();
// }

// void main() {
//   // OrderedContext ctxt = OrderedContext.empty();
//   // print("$ctxt [size = ${ctxt.size}]");

//   // Existential exvar = Existential(new Skolem(1));
//   // ctxt.insertLast(exvar);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // Existential exvar2 = Existential(new Skolem(2));
//   // ctxt.insertLast(exvar2);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // ctxt.drop(exvar2);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // Existential exvar3 = Existential(new Skolem(3));
//   // ctxt.insertLast(exvar3);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // ctxt.insertBefore(exvar2, exvar3);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // print("${ctxt.lookup(exvar3.ident)}");

//   // ctxt.drop(exvar3);
//   // exvar2.solve(IntType());
//   // print("$ctxt [size = ${ctxt.size}]");

//   // ctxt.insertBefore(exvar3, exvar);
//   // print("$ctxt [size = ${ctxt.size}]");

//   // exvar.solve(ArrowType([Skolem(5)], Skolem(4)));
//   // print("$ctxt [size = ${ctxt.size}]");

//   // print("lookup $exvar3 $exvar2 ~=~ ${ctxt.lookupAfter(exvar2.ident, exvar3)}");

//   Existential ex0 = Existential(new Skolem());
//   Existential ex1 = Existential(new Skolem());
//   Existential ex2 = Existential(new Skolem());

//   OrderedContext ctxt = OrderedContext.empty();
//   ctxt.insertLast(ex0);
//   ctxt.insertBefore(ex1, ex0);
//   ctxt.insertBefore(ex2, ex1);

//   print("$ctxt");

//   ex0.solve(ArrowType([ex1.skolem], ex2.skolem));
//   print("$ctxt");

//   Datatype ty = ex0.skolem;
//   print("$ty[$ctxt] = ${ctxt.apply(ty)} [${ctxt.verify()}]");

//   Marker m = Marker(ex0.skolem);
//   m.insertBefore(ex1);
//   ex0.solve(ArrowType([ex1.skolem], ex2.skolem));
//   // ex2.solve(ex1.skolem); // Potentially bad.
//   print("$ty[$ctxt] = ${ctxt.apply(ty)} [${ctxt.verify()}]");

//   ex1.solve(ex2.skolem);
//   print("$ty[$ctxt] = ${ctxt.apply(ty)} [${ctxt.verify()}]");

//   // ctxt.drop(ex2);
//   print("$ty[$ctxt] = ${ctxt.apply(ty)} [${ctxt.verify()}]");
//   ex2.solve(TupleType([IntType(), BoolType()]));
//   print("$ty[$ctxt] = ${ctxt.apply(ty)} [${ctxt.verify()}]");
// }
