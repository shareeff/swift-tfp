import SIL

typealias Register = String

enum BuiltinFunction {
  case check
  case rankGetter
  case shapeGetter
  case shapeSubscript
}

indirect enum Value {
  // Builtin integral type. Note that it's not for Int64, but also for Int32 or even Int1 (aka. Bool)
  case int(_ v: Int64)
  case shape(of: Register)
  case rank(of: Register)
  case dim(_ offset: Int, of: Register)
  case builtinFunction(_ kind: BuiltinFunction)
  case function(_ name: String)

  case equals(_ a: Value, _ b: Value)
}

indirect enum FrontendConstraint {
  case value(_ val: Value)
  case apply(_ functionName: String, _ result: Register, _ operands: [Register])
}

func isIntType(_ name: String) -> Bool {
  return ["Int1", "Int16", "Int32", "Int64", "Word"].contains(name)
}

func getBuiltinFunctionRef(called name: String) -> BuiltinFunction? {
  switch name {
    case "check":
      return .check
    case "$s10TensorFlow0A0V5shapeAA0A5ShapeVvg":
      return .shapeGetter
    case "$s10TensorFlow0A5ShapeVyS2icir":
      return .shapeSubscript
    case "$s10TensorFlow0A0V4rankSivg":
      return .rankGetter
    default:
      return nil
  }
}

func gatherConstraints(block: Block) -> [FrontendConstraint] {
  var constraints: [FrontendConstraint] = []
  var valuation: [Register: Value] = [:]

  for instrDef in block.instructionDefs {
    /*print(instrDef)*/
    var updates: [Value?]?

    switch instrDef.instruction {
    case let .integerLiteral(type, value):
      guard case let .selectType(baseType, elem) = type,
            case let .namedType(builtin) = baseType,
            builtin == "Builtin", isIntType(elem) else { continue }
      updates = [.int(Int64(value))]

    case let .builtin(name, operands, _):
      updates = interpret(builtinInstruction: name, operands: operands.map{ valuation[$0.value] })

    case let .functionRef(name, _):
      if let builtin = getBuiltinFunctionRef(called: name) {
        updates = [.builtinFunction(builtin)]
      } else {
        updates = [.function(name)]
      }

    // NB: Shape accessors are implemented as coroutines.
    // FIXME: Assert that the next instruction is end_apply
    case let .beginApply(_, fn, _, args, _):
        fallthrough
    case let .apply(_, fn, _, args, _):
      switch valuation[fn] {
      case let .function(name):
        updates = nil
        guard let results = instrDef.result?.valueNames else {
          fatalError("Apply instruction with no results")
        }
        guard results.count == 1 else {
          fatalError("Apply instruction with multiple results")
        }
        constraints.append(.apply(name, results[0], args))
      case .builtinFunction(.check):
        updates = nil
        guard args.count == 1 else { fatalError("Check expects a single argument") }
        if let cond = valuation[args[0]] {
          constraints.append(.value(cond))
        } else {
          print("Failed to recover a check!")
        }
      case let .builtinFunction(kind):
        updates = interpret(builtinFunction: kind, args: args, values: args.map{ valuation[$0] })
      case nil:
        updates = nil
      default:
        fatalError("Calling a non-function value")
      }

    case let .struct(type, operands):
      guard case let .namedType(typeName) = type,
            ["Bool", "Int"].contains(typeName) else { continue }
      updates = operands.map { valuation[$0.value] }

    case let .structExtract(operand, decl):
      switch decl.name {
      case ["Int", "_value"]:
        updates = [valuation[operand.value]]
      default:
        break
      }

    default:
      updates = nil
    }

    guard let results = updates else { continue }
    let resultNames = (instrDef.result?.valueNames) ?? []
    guard results.count == resultNames.count else {
      fatalError("Expected a different number of returns")
    }
    for (name, value) in zip(resultNames, results) {
      if value != nil {
        /*print(">>>>>>>> Set value of " + name + " to " + String(describing: value!))*/
      }
      valuation[name] = value
    }
  }
  return constraints
}

func interpret(builtinInstruction op: String, operands: [Value?]) -> [Value]? {
  switch op {
  case "cmp_eq_Int64":
    guard operands.count == 2 else { return nil }
    let inputs = operands.compactMap{ $0 }
    guard inputs.count == operands.count else { return nil }
    return [.equals(inputs[0], inputs[1])]
  default:
    return nil
  }
}

func interpret(builtinFunction kind: BuiltinFunction, args: [String], values: [Value?]) -> [Value?]? {
  switch kind {
  case .shapeGetter:
    guard args.count == 1 else {
      fatalError("Shape getter expected a single argument only!")
    }
    return [.shape(of: args[0])]
  case .rankGetter:
    guard args.count == 1 else {
      fatalError("Rank getter expected a single argument only!")
    }
    return [.rank(of: args[0])]
  case .shapeSubscript:
    guard args.count == 2 else {
      fatalError("Shape subscript expected two arguments")
    }
    guard case let .int(dim) = values[0] else { return nil }
    guard case let .shape(of: tensor) = values[1] else { return nil }
    // NB: We need to have two returns, because the second one is a coroutine token
    return [.dim(Int(dim), of: tensor), nil]
  case .check:
    fatalError("Checks should not be handled inside interpret")
  }
}