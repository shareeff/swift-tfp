@testable import LibShapeChecker
import SIL
import XCTest

@available(macOS 10.13, *)
final class IntegrationTests: XCTestCase {

  func testMatmulSingleArg() {
    let code = """
    @_silgen_name("f") func f(x: Tensor<Float>) -> Tensor<Float> {
      assert(x.shape[0] == 2)
      assert(x.shape[1] == 3)
      return matmul(x, x)
    }
    """
    withSIL(forSource: matmulCode + code) { module in
      let analyzer = Analyzer()
      analyzer.analyze(module: module)

      let constraints = instantiate(constraintsOf: "f", inside: analyzer.environment)
      guard !constraints.isEmpty else {
        return XCTFail("Failed to instantiate constraints for 'f'")
      }

      assertUnsat(verify(constraints))
    }
  }

  func testCustomPredicate() {
    let code = """
    func pred(_ x : TensorShape) -> Bool {
      return x[0] == 2
    }

    @_silgen_name("f")
    func f(_ x: Tensor<Float>) {
      assert(x.shape[0] == 3)
      assert(pred(x.shape))
    }
    """
    withSIL(forSource: code) { module in
      let analyzer = Analyzer()
      analyzer.analyze(module: module)
      let constraints = instantiate(constraintsOf: "f", inside: analyzer.environment)
      assertUnsat(verify(constraints))
    }
  }

  func testFactory() {
    let code = """
    @_silgen_name("f")
    func f() {
      let x = randn([2, 3])
      assert(x.shape[0] == 3)
    }
    """
    withSIL(forSource: randnCode + code) { module in
      let analyzer = Analyzer()
      analyzer.analyze(module: module)
      let constraints = instantiate(constraintsOf: "f", inside: analyzer.environment)
      assertUnsat(verify(constraints))
    }
  }


  static var allTests = [
    ("testMatmulSingleArg", testMatmulSingleArg),
    ("testCustomPredicate", testCustomPredicate),
    ("testFactory", testFactory),
  ]
}

