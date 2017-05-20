
use "collections"

trait _ASTDef
  fun name(): String
  fun code_gen(g: CodeGen)

class _ASTDefFixed is _ASTDef
  let _gen: ASTGen
  let _name: String
  let _traits: Array[String] = Array[String] // TODO: remove and use unions only
  
  let fields: List[(String, String, String)] = fields.create()
  
  var _todo:       Bool = false
  var _with_scope: Bool = false
  var _with_type:  Bool = false
  
  new create(g: ASTGen, n: String) =>
    (_gen, _name) = (g, n)
    _gen.defs.push(this)
  
  fun ref has(n: String, t: String, d: String = "") => fields.push((n, t, d))
  
  fun ref todo()       => _todo       = true
  fun ref with_scope() => _with_scope = true
  fun ref with_type()  => _with_type  = true
  
  fun ref in_union(n: String, n2: String = "") =>
    _traits.push(n)
    if n2.size() > 0 then _traits.push(n2) end
    _gen._add_to_union(n, _name)
    if n2.size() > 0 then _gen._add_to_union(n2, n) end
  
  fun name(): String => _name
  
  fun code_gen(g: CodeGen) =>
    g.line("class " + _name + " is ")
    if _traits.size() == 0 then
      g.add("AST")
    else
      g.add("(AST")
      for t in _traits.values() do g.add(" & " + t) end
      g.add(")")
    end
    if _todo then g.add(" // TODO") end
    g.push_indent()
    
    // Declare common fields.
    g.line("var _pos: SourcePosAny = SourcePosNone")
    g.line()
    
    // Declare all fields.
    for (field_name, field_type, _) in fields.values() do
      g.line("var _" + field_name + ": " + field_type)
    end
    if fields.size() > 0 then g.line() end
    
    // Declare a constructor that initializes all fields from parameters.
    g.line("new create(")
    var iter = fields.values()
    g.push_indent()
    for (field_name, field_type, field_default) in iter do
      g.line(field_name + "': " + field_type)
      if field_default.size() > 0 then g.add(" = " + field_default) end
      if iter.has_next() then g.add(",") end
    end
    g.add(")")
    g.pop_indent()
    if fields.size() == 0 then
      g.add(" => None")
    else
      g.line("=>")
      g.push_indent()
      for (field_name, field_type, _) in fields.values() do
        g.line("_" + field_name + " = " + field_name + "'")
      end
      g.pop_indent()
    end
    if fields.size() > 0 then g.line() end
    
    // Declare a constructor that initializes all fields from an iterator.
    g.block(
      """
      new from_iter(
        iter: Iterator[(AST | None)],
        pos': SourcePosAny = SourcePosNone,
        err: {(String, SourcePosAny)} = {(s: String, p: SourcePosAny) => None } ref)?
      =>
      """)
    g.push_indent()
    g.line("_pos = pos'")
    g.line()
    
    var iter_next = "iter.next()"
    for (field_name, field_type, field_default) in fields.values() do
      if (try field_type.find("Array[") == 0 else false end) then
        let elem_type: String = field_type.substring(6, -1)
        g.line("let " + field_name + "' = " + field_type)
        g.line("var " + field_name + "_next' = ")
        if iter_next != "iter.next()" then
          g.add(iter_next)
        else
          g.add("try iter.next() else None end")
        end
        g.line("while true do")
        g.push_indent()
        g.line("try " + field_name + "'.push(" + field_name + "_next'")
        g.add(" as " + elem_type + ") else break end")
        g.line("try " + field_name + "_next' = iter.next()")
        g.add(" else " + field_name + "_next' = None; break end")
        g.pop_indent()
        g.line("end")
        iter_next = field_name + "_next'"
      else
        g.line("let " + field_name + "': (AST | None) =")
        if iter_next != "iter.next()" then
          g.add(" " + iter_next)
        else
          if field_default.size() > 0 then
            g.add(" try iter.next() else " + field_default + " end")
          else
            g.push_indent()
            g.line("try iter.next()")
            g.line("else err(\"missing required field: " + field_name + "\"")
            g.add(", pos'); error")
            g.line("end")
            g.pop_indent()
          end
        end
        iter_next = "iter.next()"
      end
    end
    
    if iter_next != "iter.next()" then
      g.line("if " + iter_next + " isnt None then")
      g.push_indent()
      g.line("let extra' = " + iter_next)
      g.line("err(\"unexpected extra field\", try (extra' as AST).pos() else SourcePosNone end); error")
      g.pop_indent()
      g.line("end")
    else
      g.line("if")
      g.push_indent()
      g.line("try")
      g.push_indent()
      g.line("let extra' = " + iter_next)
      g.line("err(\"unexpected extra field\", try (extra' as AST).pos() else SourcePosNone end); true")
      g.pop_indent()
      g.line("else false")
      g.line("end")
      g.pop_indent()
      g.line("then error end")
    end
    
    if fields.size() > 0 then g.line() end
    for (field_name, field_type, field_default) in fields.values() do
      g.line("_" + field_name + " =")
      if (try field_type.find("Array[") == 0 else false end) then
        g.add(" " + field_name + "'")
      else
        g.push_indent()
        g.line("try " + field_name + "' as " + field_type)
        g.line("else err(\"incompatible field: " + field_name)
        g.add("\", try (" + field_name + "' as AST).pos() else SourcePosNone end); error")
        g.line("end")
        g.pop_indent()
      end
    end
    
    g.pop_indent()
    g.line()
    
    // Declare common getters and setters.
    g.line("fun pos(): SourcePosAny => _pos")
    g.line("fun ref set_pos(pos': SourcePosAny) => _pos = pos'")
    g.line()
    
    // Declare getter methods for all fields.
    for (field_name, field_type, _) in fields.values() do
      g.line("fun " + field_name + "(): this->" + field_type + " => ")
      g.add("_" + field_name)
    end
    if fields.size() > 0 then g.line() end
    
    // Declare setter methods for all fields.
    for (field_name, field_type, field_default) in fields.values() do
      g.line("fun ref set_" + field_name + "(")
      g.add(field_name + "': " + field_type)
      if field_default.size() > 0 then g.add(" = " + field_default) end
      g.add(") => ")
      g.add("_" + field_name + " = consume " + field_name + "'")
    end
    if fields.size() > 0 then g.line() end
    
    // Declare a string method to print itself.
    g.line("fun string(): String iso^ =>")
    g.push_indent()
    g.line("let s = recover iso String end")
    g.line("s.append(\"" + _name + "\")")
    if fields.size() > 0 then
      g.line("s.push('(')")
      iter = fields.values()
      for (field_name, field_type, _) in iter do
        if field_type.at("Array[", 0) then
          g.line("s.push('[')")
          g.line("for (i, v) in _" + field_name + ".pairs() do")
          g.push_indent()
          g.line("if i > 0 then s.>push(';').push(' ') end")
          g.line("s.append(v.string())")
          g.pop_indent()
          g.line("end")
          g.line("s.push(']')")
          if iter.has_next() then g.line("s.>push(',').push(' ')") end
        else
          g.line("s.>append(_" + field_name + ".string())")
          if iter.has_next() then g.add(".>push(',').push(' ')") end
        end
      end
      g.line("s.push(')')")
    end
    g.line("consume s")
    g.pop_indent()
    
    g.pop_indent()
    g.line()

class _ASTDefWrap is _ASTDef
  let _gen: ASTGen
  let _name: String
  let value_type: String
  let _traits: Array[String] = Array[String] // TODO: remove and use unions only
  
  new create(g: ASTGen, n: String, t: String) =>
    (_gen, _name, value_type) = (g, n, t)
    _gen.defs.push(this)
  
  fun ref in_union(n: String, n2: String = "") =>
    _traits.push(n)
    if n2.size() > 0 then _traits.push(n2) end
    _gen._add_to_union(n, _name)
    if n2.size() > 0 then _gen._add_to_union(n2, n) end
  
  fun name(): String => _name
  
  fun code_gen(g: CodeGen) =>
    g.line("class " + _name + " is ")
    if _traits.size() == 0 then
      g.add("AST")
    else
      g.add("(AST")
      for t in _traits.values() do g.add(" & " + t) end
      g.add(")")
    end
    g.push_indent()
    
    // Declare common fields.
    g.line("var _pos: SourcePosAny = SourcePosNone")
    
    // Declare the value field.
    g.line("var _value: " + value_type)
    
    // Declare a constructor that initializes the value field from a parameter.
    g.line("new create(value': " + value_type + ") => _value = value'")
    
    g.block(
      """
      new from_iter(
        iter: Iterator[(AST | None)],
        pos': SourcePosAny = SourcePosNone,
        err: {(String, SourcePosAny)} = {(s: String, p: SourcePosAny) => None } ref)?
      =>
      """)
    g.push_indent()
    g.line("_pos = pos'")
    if value_type == "String" then
      g.line("_value = \"foo\" // TODO: parse from _pos?")
    else
      g.line("_value = 88 // TODO: parse from _pos?")
    end
    g.line()
    g.line("if")
    g.push_indent()
    g.line("try")
    g.push_indent()
    g.line("let extra' = iter.next()")
    g.line("err(\"unexpected extra field\", try (extra' as AST).pos() else SourcePosNone end); true")
    g.pop_indent()
    g.line("else false")
    g.line("end")
    g.pop_indent()
    g.line("then error end")
    g.pop_indent()
    g.line()
    
    // Declare common getters and setters.
    g.line("fun pos(): SourcePosAny => _pos")
    g.line("fun ref set_pos(pos': SourcePosAny) => _pos = pos'")
    g.line()
    
    // Declare a getter method for the value field.
    g.line("fun value(): " + value_type + " => _value")
    
    // Declare a setter methods for the value field.
    g.line("fun ref set_value(value': " + value_type + ") => _value = value'")
    
    // Declare a string method to print itself.
    g.line("fun string(): String iso^ =>")
    g.push_indent()
    g.line("recover")
    g.push_indent()
    g.line("String.>append(\"" + _name + "(\")")
    g.add(".>append(_value.string()).>push(')')")
    g.pop_indent()
    g.line("end")
    g.pop_indent()
    
    g.pop_indent()
    g.line()

class _ASTDefLexeme is _ASTDef
  let _gen: ASTGen
  let _name: String
  let _traits: Array[String] = Array[String] // TODO: remove and use unions only
  
  new create(g: ASTGen, n: String) =>
    (_gen, _name) = (g, n)
    _gen.defs.push(this)
  
  fun ref in_union(n: String, n2: String = "") =>
    _traits.push(n)
    if n2.size() > 0 then _traits.push(n2) end
    _gen._add_to_union(n, _name)
    if n2.size() > 0 then _gen._add_to_union(n2, n) end
  
  fun name(): String => _name
  
  fun code_gen(g: CodeGen) =>
    g.line("class " + _name + " is ")
    if _traits.size() == 0 then
      g.add("AST")
    else
      g.add("(AST")
      for t in _traits.values() do g.add(" & " + t) end
      g.add(")")
    end
    g.push_indent()
    
    // Declare common fields.
    g.line("var _pos: SourcePosAny = SourcePosNone")
    
    // Declare a constructor that does nothing.
    g.line("new create() => None")
    
    // Declare a constructor that accepts an iterator but always errors.
    g.block(
      """
      new from_iter(
        iter: Iterator[(AST | None)],
        pos': SourcePosAny = SourcePosNone,
        err: {(String, SourcePosAny)} = {(s: String, p: SourcePosAny) => None } ref)?
      =>
      """)
    g.push_indent()
    g.line("err(\"this lexeme-only type should never be built\", pos'); error")
    g.pop_indent()
    g.line()
    
    // Declare common getters and setters.
    g.line("fun pos(): SourcePosAny => _pos")
    g.line("fun ref set_pos(pos': SourcePosAny) => _pos = pos'")
    g.line()
    
    // Declare a string method to print itself.
    g.line("fun string(): String iso^ =>")
    g.push_indent()
    g.line("recover String.>append(\"" + _name + "\") end")
    g.pop_indent()
    
    g.pop_indent()
    g.line()
