/*
 * Copyright 2023 WebAssembly Community Group participants
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "ir/names.h"
#include "ir/utils.h"
#include "pass.h"
#include "passes/stringify-walker.h"
#include "support/suffix_tree.h"
#include "wasm.h"

#define OUTLINING_DEBUG 0

#if OUTLINING_DEBUG
#define ODBG(statement) statement
#else
#define ODBG(statement)
#endif

// Check a Result or MaybeResult for error and call Fatal() if the error exists.
#define ASSERT_OK(val)                                                         \
  if (auto _val = (val); auto err = _val.getErr()) {                           \
    Fatal() << err->msg;                                                       \
  }

namespace wasm {

struct OutliningSequence {
  unsigned startIdx;
  unsigned endIdx;
  Name func;
  bool endsTypeUnreachable;
#if OUTLINING_DEBUG
  unsigned programIdx;
#endif

  OutliningSequence(unsigned startIdx,
                    unsigned endIdx,
                    Name func,
                    bool endsTypeUnreachable
#if OUTLINING_DEBUG
                    ,
                    unsigned programIdx
#endif
                    )
    : startIdx(startIdx), endIdx(endIdx), func(func),
      endsTypeUnreachable(endsTypeUnreachable)
#if OUTLINING_DEBUG
      ,
      programIdx(programIdx)
#endif
  {
  }
};

// Instances of this walker are intended to walk a function at a time, at the
// behest of the owner of the instance.
struct ReconstructStringifyWalker
  : public StringifyWalker<ReconstructStringifyWalker> {

  ReconstructStringifyWalker(Module* wasm, Function* func)
    : existingBuilder(*wasm), outlinedBuilder(*wasm), func(func) {
    this->setModule(wasm);
    ODBG(std::cerr << "\nexistingBuilder: " << &existingBuilder
                   << " outlinedBuilder: " << &outlinedBuilder << "\n");
  }

  // As we reconstruct the IR during outlining, we need to know what
  // state we're in to determine which IRBuilder to send the instruction to.
  enum ReconstructState {
    NotInSeq = 0,  // Will not be outlined into a new function.
    InSeq = 1,     // Currently being outlined into a new function.
    InSkipSeq = 2, // A sequence that has already been outlined.
  };
  // We begin with the assumption that we are not currently in a sequence that
  // will be outlined.
  ReconstructState state = ReconstructState::NotInSeq;

  // The list of sequences that will be outlined, contained in the function
  // currently being walked.
  std::vector<OutliningSequence> sequences;
  // Tracks the OutliningSequence the walker is about to outline or is currently
  // outlining.
  uint32_t seqCounter = 0;
  // Counts the number of instructions visited since the function began,
  // corresponds to the indices in the sequences.
  uint32_t instrCounter = 0;
  // A reusable builder for reconstructing the function that will have sequences
  // of instructions removed to be placed into an outlined function. The removed
  // sequences will be replaced by a call to the outlined function.
  IRBuilder existingBuilder;
  // A reusable builder for constructing the outlined functions that will
  // contain repeat sequences found in the program.
  IRBuilder outlinedBuilder;

  // The function we are outlining from.
  Function* func;

  void addUniqueSymbol(SeparatorReason reason) {
    if (auto curr = reason.getFuncStart()) {
      startExistingFunction(curr->func);
      return;
    }

    // instrCounter is managed manually and incremented at the beginning of
    // addUniqueSymbol() and visitExpression(), except for the case where we are
    // starting a new function, as that resets the counters back to 0.
    instrCounter++;

    ODBG(std::string desc);
    if (auto curr = reason.getBlockStart()) {
      ODBG(desc = "Block Start at ");
      ASSERT_OK(existingBuilder.visitBlockStart(curr->block));
    } else if (auto curr = reason.getIfStart()) {
      // IR builder needs the condition of the If pushed onto the builder before
      // visitIfStart(), which will expect to be able to pop the condition.
      // This is always okay to do because the correct condition was installed
      // onto the If when the outer scope was visited.
      existingBuilder.pushSynthetic(curr->iff->condition);
      ODBG(desc = "If Start at ");
      ASSERT_OK(existingBuilder.visitIfStart(curr->iff));
    } else if (reason.getElseStart()) {
      ODBG(desc = "Else Start at ");
      ASSERT_OK(existingBuilder.visitElse());
    } else if (auto curr = reason.getLoopStart()) {
      ODBG(desc = "Loop Start at ");
      ASSERT_OK(existingBuilder.visitLoopStart(curr->loop));
    } else if (auto curr = reason.getTryStart()) {
      // We preserve the name of the tryy because IRBuilder expects
      // visitTryStart() to be called on an empty Try, during the normal case of
      // parsing. TODO: Fix this.
      auto name = curr->tryy->name;
      ASSERT_OK(existingBuilder.visitTryStart(curr->tryy, Name()));
      ODBG(desc = "Try Start at ");
      curr->tryy->name = name;
    } else if (auto curr = reason.getCatchStart()) {
      ASSERT_OK(existingBuilder.visitCatch(curr->tag));
      ODBG(desc = "Catch Start at ");
    } else if (reason.getCatchAllStart()) {
      ASSERT_OK(existingBuilder.visitCatchAll());
      ODBG(desc = "Catch All Start at");
    } else if (auto curr = reason.getTryTableStart()) {
      ODBG(desc = "Try Table Start at ");
      ASSERT_OK(existingBuilder.visitTryTableStart(curr->tryt));
    } else if (reason.getEnd()) {
      ODBG(desc = "End at ");
      ASSERT_OK(existingBuilder.visitEnd());
      // Reset the function in case we just ended the function scope.
      existingBuilder.setFunction(func);
      // Outlining performs an unnested walk of the Wasm module, visiting
      // each scope one at a time. IRBuilder, in contrast, expects to
      // visit several nested scopes at a time. Thus, calling end() finalizes
      // the control flow and places it on IRBuilder's internal stack, ready for
      // the enclosing scope to consume its expressions off the stack. Since
      // outlining walks unnested, the enclosing scope never arrives to retrieve
      // its expressions off the stack, so we must call build() after visitEnd()
      // to clear the internal stack IRBuilder manages.
      ASSERT_OK(existingBuilder.build());
    } else {
      ODBG(desc = "addUniqueSymbol for unimplemented control flow ");
      WASM_UNREACHABLE("unimplemented control flow");
    }
    ODBG(printAddUniqueSymbol(desc));
  }

  void visitExpression(Expression* curr) {
    maybeBeginSeq();

    IRBuilder* builder = state == InSeq      ? &outlinedBuilder
                         : state == NotInSeq ? &existingBuilder
                                             : nullptr;
    if (builder) {
      if (auto* expr = curr->dynCast<Break>()) {
        Type type = expr->value ? expr->value->type : Type::none;
        ASSERT_OK(builder->visitBreakWithType(expr, type));
      } else if (auto* expr = curr->dynCast<Switch>()) {
        Type type = expr->value ? expr->value->type : Type::none;
        ASSERT_OK(builder->visitSwitchWithType(expr, type));
      } else {
        // Assert ensures new unhandled branch instructions
        // will quickly cause an error. Serves as a reminder to
        // implement a new special-case visit*WithType.
        assert(curr->is<BrOn>() || !Properties::isBranch(curr));
        ASSERT_OK(builder->visit(curr));
      }
    }
    ODBG(printVisitExpression(curr));

    if (state == InSeq || state == InSkipSeq) {
      maybeEndSeq();
    }
  }

  // Helpers
  void startExistingFunction(Function* func) {
    ASSERT_OK(existingBuilder.build());
    ASSERT_OK(existingBuilder.visitFunctionStart(func));
    instrCounter = 0;
    seqCounter = 0;
    state = NotInSeq;
    ODBG(std::cerr << "\n"
                   << "Func Start to $" << func->name << " at "
                   << &existingBuilder << "\n");
  }

  ReconstructState getCurrState() {
    // We are either in a sequence or not in a sequence. If we are in a sequence
    // and have already created the body of the outlined function that will be
    // called, then we will skip instructions, otherwise we add the instructions
    // to the outlined function. If we are not in a sequence, then the
    // instructions are sent to the existing function.
    if (seqCounter < sequences.size() &&
        instrCounter >= sequences[seqCounter].startIdx &&
        instrCounter < sequences[seqCounter].endIdx) {
      return getModule()->getFunction(sequences[seqCounter].func)->body
               ? InSkipSeq
               : InSeq;
    }
    return NotInSeq;
  }

  void maybeBeginSeq() {
    instrCounter++;
    auto currState = getCurrState();
    if (currState != state) {
      switch (currState) {
        case NotInSeq:
          break;
        case InSeq:
          transitionToInSeq();
          break;
        case InSkipSeq:
          transitionToInSkipSeq();
          break;
      }
    }
    state = currState;
  }

  void transitionToInSeq() {
    Function* outlinedFunc =
      getModule()->getFunction(sequences[seqCounter].func);
    ASSERT_OK(outlinedBuilder.visitFunctionStart(outlinedFunc));

    // Make a call from the existing function to the outlined function. This
    // call will replace the instructions moved to the outlined function.
    ODBG(std::cerr << "\nadding call " << outlinedFunc->name << " to "
                   << &existingBuilder << "\n");
    ASSERT_OK(existingBuilder.makeCall(outlinedFunc->name, false));

    // If the last instruction of the outlined sequence is unreachable, insert
    // an unreachable instruction immediately after the call to the outlined
    // function. This maintains the unreachable type in the original scope
    // of the outlined sequence.
    if (sequences[seqCounter].endsTypeUnreachable) {
      ODBG(std::cerr << "\nadding endsUnreachable to " << &existingBuilder
                     << "\n");
      ASSERT_OK(existingBuilder.makeUnreachable());
    }

    // Add a local.get instruction for every parameter of the outlined function.
    Signature sig = outlinedFunc->type.getSignature();
    ODBG(std::cerr << outlinedFunc->name << " takes " << sig.params.size()
                   << " parameters\n");
    for (Index i = 0; i < sig.params.size(); i++) {
      ODBG(std::cerr << "adding local.get $" << i << " to " << &outlinedBuilder
                     << "\n");
      ASSERT_OK(outlinedBuilder.makeLocalGet(i));
    }
  }

  void transitionToInSkipSeq() {
    Function* outlinedFunc =
      getModule()->getFunction(sequences[seqCounter].func);
    ODBG(std::cerr << "\nstarting to skip instructions "
                   << sequences[seqCounter].startIdx << " - "
                   << sequences[seqCounter].endIdx - 1 << " to "
                   << sequences[seqCounter].func
                   << " and adding call() instead\n");
    ASSERT_OK(existingBuilder.makeCall(outlinedFunc->name, false));
    // If the last instruction of the outlined sequence is unreachable, insert
    // an unreachable instruction immediately after the call to the outlined
    // function. This maintains the unreachable type in the original scope
    // of the outlined sequence.
    if (sequences[seqCounter].endsTypeUnreachable) {
      ASSERT_OK(existingBuilder.makeUnreachable());
    }
  }

  void maybeEndSeq() {
    if (instrCounter + 1 == sequences[seqCounter].endIdx) {
      transitionToNotInSeq();
      state = NotInSeq;
    }
  }

  void transitionToNotInSeq() {
    ODBG(std::cerr << "End of sequence ");
    if (state == InSeq) {
      ODBG(std::cerr << "to " << &outlinedBuilder);
      ASSERT_OK(outlinedBuilder.visitEnd());
    }
    ODBG(std::cerr << "\n\n");
    // Completed a sequence so increase the seqCounter and reset the state.
    seqCounter++;
  }

#if OUTLINING_DEBUG
  void printAddUniqueSymbol(std::string desc) {
    std::cerr << desc << std::to_string(instrCounter) << " to "
              << &existingBuilder << "\n";
  }

  void printVisitExpression(Expression* curr) {
    auto* builder = state == InSeq      ? &outlinedBuilder
                    : state == NotInSeq ? &existingBuilder
                                        : nullptr;
    auto verb = state == InSkipSeq ? "skipping " : "adding ";
    std::cerr << verb << std::to_string(instrCounter) << ": "
              << ShallowExpression{curr} << "(" << curr << ") to " << builder
              << "\n";
  }
#endif
};

struct Outlining : public Pass {
  void run(Module* module) {
    HashStringifyWalker stringify;
    // Walk the module and create a "string representation" of the program.
    stringify.walkModule(module);
    ODBG(printHashString(stringify.hashString, stringify.exprs));
    // Collect all of the substrings of the string representation that appear
    // more than once in the program.
    auto substrings =
      StringifyProcessor::repeatSubstrings(stringify.hashString);
    // Remove substrings that are substrings of longer repeat substrings.
    substrings = StringifyProcessor::dedupe(substrings);
    // Remove substrings with overlapping indices.
    substrings = StringifyProcessor::filterOverlaps(substrings);
    // Remove substrings with branch, return, and try_table instructions until
    // an analysis is performed to see if the intended destination of the branch
    // is included in the substring to be outlined.
    substrings =
      StringifyProcessor::filterBranches(substrings, stringify.exprs);
    // Remove substrings with local.set instructions until Outlining is extended
    // to support arranging for the written values to be returned from the
    // outlined function and written back to the original locals.
    substrings =
      StringifyProcessor::filterLocalSets(substrings, stringify.exprs);
    // Remove substrings with local.get instructions until Outlining is extended
    // to support passing the local values as additional arguments to the
    // outlined function.
    substrings =
      StringifyProcessor::filterLocalGets(substrings, stringify.exprs);
    // Convert substrings to sequences that are more easily outlineable as we
    // walk the functions in a module. Sequences contain indices that
    // are relative to the enclosing function while substrings have indices
    // relative to the entire program.
    auto sequences = makeSequences(module, substrings, stringify);
    outline(module,
            sequences
#if OUTLINING_DEBUG
            ,
            stringify
#endif
    );
    // Position the outlined functions first in the functions vector to make
    // the outlining lit tests far more readable.
    moveOutlinedFunctions(module, substrings.size());

    // Because we visit control flow in stringified order rather than normal
    // postorder, IRBuilder is not able to properly track branches, so it may
    // not have finalized blocks with the correct types. ReFinalize now to fix
    // any issues.
    PassRunner runner(getPassRunner());
    runner.add(std::make_unique<ReFinalize>());
    runner.run();
  }

  Name addOutlinedFunction(Module* module,
                           const SuffixTree::RepeatedSubstring& substring,
                           const std::vector<Expression*>& exprs) {
    auto startIdx = substring.StartIndices[0];
    // The outlined functions can be named anything.
    Name func = Names::getValidFunctionName(*module, std::string("outline$"));
    // Calculate the function signature for the outlined sequence.
    StackSignature sig;
    for (uint32_t exprIdx = startIdx; exprIdx < startIdx + substring.Length;
         exprIdx++) {
      sig += StackSignature(exprs[exprIdx]);
    }
    module->addFunction(
      Builder::makeFunction(func, Signature(sig.params, sig.results), {}));
    return func;
  }

  using Sequences =
    std::unordered_map<Name, std::vector<wasm::OutliningSequence>>;

  // Converts an array of SuffixTree::RepeatedSubstring to a mapping of original
  // functions to repeated sequences they contain. These sequences are ordered
  // by start index by construction because the substring's start indices are
  // ordered.
  Sequences makeSequences(Module* module,
                          const Substrings& substrings,
                          const HashStringifyWalker& stringify) {
    Sequences seqByFunc;
    for (auto& substring : substrings) {
      auto func = addOutlinedFunction(module, substring, stringify.exprs);
      for (auto seqIdx : substring.StartIndices) {
        // seqIdx is relative to the entire program; making the idx of the
        // sequence relative to its function is better for outlining because we
        // walk functions.
        auto [relativeIdx, existingFunc] = stringify.makeRelative(seqIdx);
        auto seq = OutliningSequence(
          relativeIdx,
          relativeIdx + substring.Length,
          func,
          stringify.exprs[seqIdx + substring.Length - 1]->type ==
            Type::unreachable
#if OUTLINING_DEBUG
          ,
          seqIdx
#endif
        );
        seqByFunc[existingFunc].push_back(seq);
      }
    }
    return seqByFunc;
  }

  void outline(Module* module,
               Sequences seqByFunc
#if OUTLINING_DEBUG
               ,
               const HashStringifyWalker& stringify
#endif
  ) {
    // TODO: Make this a function-parallel sub-pass.
    std::vector<Name> keys(seqByFunc.size());
    std::transform(seqByFunc.begin(),
                   seqByFunc.end(),
                   keys.begin(),
                   [](auto pair) { return pair.first; });
    for (auto func : keys) {
      // During function reconstruction, a walker iterates thru each instruction
      // of a function, incrementing a counter to find matching sequences. As a
      // result, the sequences of a function must be sorted by
      // smallest start index, otherwise reconstruction will miss outlining a
      // repeat sequence.
      std::sort(seqByFunc[func].begin(),
                seqByFunc[func].end(),
                [](OutliningSequence a, OutliningSequence b) {
                  return a.startIdx < b.startIdx;
                });
      ReconstructStringifyWalker reconstruct(module, module->getFunction(func));
      reconstruct.sequences = std::move(seqByFunc[func]);
      ODBG(printReconstruct(module,
                            stringify.hashString,
                            stringify.exprs,
                            func,
                            reconstruct.sequences));
      reconstruct.doWalkFunction(module->getFunction(func));
    }
  }

  void moveOutlinedFunctions(Module* module, uint32_t outlinedCount) {
    // Rearrange outlined functions to the beginning of the functions vector by
    // using std::make_move_iterator to avoid making copies. A temp vector is
    // created to avoid iterator invalidation.
    auto count = module->functions.size();
    std::vector<std::unique_ptr<Function>> temp(
      std::make_move_iterator(module->functions.end() - outlinedCount),
      std::make_move_iterator(module->functions.end()));
    module->functions.insert(module->functions.begin(),
                             std::make_move_iterator(temp.begin()),
                             std::make_move_iterator(temp.end()));
    module->functions.resize(count);
    // After the functions vector is directly manipulated, we need to call
    // updateFunctionsMap().
    module->updateFunctionsMap();
  }

#if OUTLINING_DEBUG
  void printHashString(const std::vector<uint32_t>& hashString,
                       const std::vector<Expression*>& exprs) {
    std::cerr << "\n\n";
    for (Index idx = 0; idx < hashString.size(); idx++) {
      Expression* expr = exprs[idx];
      if (expr) {
        std::cerr << idx << " - " << hashString[idx] << ": "
                  << ShallowExpression{expr} << "\n";
      } else {
        std::cerr << idx << ": unique symbol\n";
      }
    }
  }
  void printReconstruct(Module* module,
                        const std::vector<uint32_t>& hashString,
                        const std::vector<Expression*>& exprs,
                        Name existingFunc,
                        const std::vector<OutliningSequence>& seqs) {
    std::cerr << "\n\nReconstructing existing fn: " << existingFunc << "\n";
    std::cerr << "moving sequences: "
              << "\n";
    for (auto& seq : seqs) {
      for (Index idx = seq.programIdx;
           idx < seq.programIdx + (seq.endIdx - seq.startIdx);
           idx++) {
        Expression* expr = exprs[idx];
        if (expr == nullptr) {
          std::cerr << "unique symbol\n";
        } else {
          std::cerr << idx << " - " << hashString[idx] << " - " << seq.startIdx
                    << " : " << ShallowExpression{expr} << "\n";
        }
      }
      std::cerr << "to outlined function: " << seq.func << "\n";
      auto outlinedFunction = module->getFunction(seq.func);
      std::cerr << "with signature: " << outlinedFunction->type.toString()
                << "\n";
    }
  }
#endif
};

Pass* createOutliningPass() { return new Outlining(); }

} // namespace wasm
