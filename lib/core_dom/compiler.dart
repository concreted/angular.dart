part of angular.core.dom;

@NgInjectableService()
class Compiler {
  final Profiler _perf;
  final Parser _parser;
  final AstParser _astParser;
  final Expando _expando;

  Compiler(this._perf, this._parser, this._astParser, this._expando);

  _compileBlock(NodeCursor domCursor, NodeCursor templateCursor,
                List<DirectiveRef> useExistingDirectiveRefs,
                DirectiveMap directives) {
    if (domCursor.nodeList().length == 0) return null;

    var directivePositions = null; // don't pre-create to create sparse tree and prevent GC pressure.
    var cursorAlreadyAdvanced;

    do {
      var declaredDirectiveRefs = useExistingDirectiveRefs == null
          ?  directives.selector(domCursor.nodeList()[0])
          : useExistingDirectiveRefs;
      var children = NgAnnotation.COMPILE_CHILDREN;
      var childDirectivePositions = null;
      List<DirectiveRef> usableDirectiveRefs = null;

      cursorAlreadyAdvanced = false;

      for (var j = 0, jj = declaredDirectiveRefs.length; j < jj; j++) {
        DirectiveRef directiveRef = declaredDirectiveRefs[j];
        NgAnnotation annotation = directiveRef.annotation;
        var blockFactory = null;

        if (annotation.children != children &&
            children == NgAnnotation.COMPILE_CHILDREN) {
          children = annotation.children;
        }

        if (children == NgAnnotation.TRANSCLUDE_CHILDREN) {
          var remainingDirectives = declaredDirectiveRefs.sublist(j + 1);
          blockFactory = compileTransclusion(
              domCursor, templateCursor,
              directiveRef, remainingDirectives, directives);

          j = jj; // stop processing further directives since they belong to transclusion;
        }
        if (usableDirectiveRefs == null) {
          usableDirectiveRefs = [];
        }
        directiveRef.blockFactory = blockFactory;
        createMappings(directiveRef);
        usableDirectiveRefs.add(directiveRef);
      }

      if (children == NgAnnotation.COMPILE_CHILDREN && domCursor.descend()) {
        templateCursor.descend();

        childDirectivePositions =
            _compileBlock(domCursor, templateCursor, null, directives);

        domCursor.ascend();
        templateCursor.ascend();
      }

      if (childDirectivePositions != null || usableDirectiveRefs != null) {
        if (directivePositions == null) directivePositions = [];
        var directiveOffsetIndex = templateCursor.index;

        directivePositions
            ..add(directiveOffsetIndex)
            ..add(usableDirectiveRefs)
            ..add(childDirectivePositions);
      }
    } while (templateCursor.microNext() && domCursor.microNext());

    return directivePositions;
  }

  BlockFactory compileTransclusion(
                      NodeCursor domCursor, NodeCursor templateCursor,
                      DirectiveRef directiveRef,
                      List<DirectiveRef> transcludedDirectiveRefs,
                      DirectiveMap directives) {
    var anchorName = directiveRef.annotation.selector + (directiveRef.value != null ? '=' + directiveRef.value : '');
    var blockFactory;
    var blocks;

    var transcludeCursor = templateCursor.replaceWithAnchor(anchorName);
    var domCursorIndex = domCursor.index;
    var directivePositions =
        _compileBlock(domCursor, transcludeCursor, transcludedDirectiveRefs, directives);
    if (directivePositions == null) directivePositions = [];

    blockFactory = new BlockFactory(transcludeCursor.elements, directivePositions, _perf, _expando);
    domCursor.index = domCursorIndex;

    if (domCursor.isInstance()) {
      domCursor.insertAnchorBefore(anchorName);
      blocks = [blockFactory(domCursor.nodeList())];
      domCursor.macroNext();
      templateCursor.macroNext();
      while (domCursor.isValid() && domCursor.isInstance()) {
        blocks.add(blockFactory(domCursor.nodeList()));
        domCursor.macroNext();
        templateCursor.remove();
      }
    } else {
      domCursor.replaceWithAnchor(anchorName);
    }

    return blockFactory;
  }

  BlockFactory call(List<dom.Node> elements, DirectiveMap directives) {
    var timerId;
    assert((timerId = _perf.startTimer('ng.compile', _html(elements))) != false);
    List<dom.Node> domElements = elements;
    List<dom.Node> templateElements = cloneElements(domElements);
    var directivePositions = _compileBlock(
        new NodeCursor(domElements), new NodeCursor(templateElements),
        null, directives);

    var blockFactory = new BlockFactory(templateElements,
        directivePositions == null ? [] : directivePositions, _perf, _expando);

    assert(_perf.stopTimer(timerId) != false);
    return blockFactory;
  }

  static RegExp _MAPPING = new RegExp(r'^(\@|=\>\!|\=\>|\<\=\>|\&)\s*(.*)$');

  createMappings(DirectiveRef ref) {
    NgAnnotation annotation = ref.annotation;
    if (annotation.map != null) annotation.map.forEach((attrName, mapping) {
      Match match = _MAPPING.firstMatch(mapping);
      if (match == null) {
        throw "Unknown mapping '$mapping' for attribute '$attrName'.";
      }
      var mode = match[1];
      var dstPath = match[2];

      String dstExpression = dstPath.isEmpty ? attrName : dstPath;
      Expression dstPathFn = _parser(dstExpression);
      if (!dstPathFn.isAssignable) {
        throw "Expression '$dstPath' is not assignable in mapping '$mapping' for attribute '$attrName'.";
      }
      ApplyMapping mappingFn;
      switch (mode) {
        case '@':
          mappingFn = (NodeAttrs attrs, Scope scope, Object controller, FilterMap filters) {
            attrs.observe(attrName, (value) => dstPathFn.assign(controller, value));
          };
          break;
        case '<=>':
          mappingFn = (NodeAttrs attrs, Scope scope, Object controller, FilterMap filters) {
            if (attrs[attrName] == null) return;
            String expression = attrs[attrName];
            Expression expressionFn = _parser(expression);
            var blockOutbound = false;
            var blockInbound = false;
            scope.watch(
                _astParser(expression, filters: filters),
                (inboundValue, _) {
                  if (!blockInbound) {
                    blockOutbound = true;
                    scope.rootScope.runAsync(() => blockOutbound = false);
                    return dstPathFn.assign(controller, inboundValue);
                  }
                }
            );
            if (expressionFn.isAssignable) {
              scope.watch(
                  _astParser(dstExpression, context: controller, filters: filters),
                  (outboundValue, _) {
                    if(!blockOutbound) {
                      blockInbound = true;
                      scope.rootScope.runAsync(() => blockInbound = false);
                      expressionFn.assign(scope.context, outboundValue);
                    }
                  }
              );
            }
          };
          break;
        case '=>':
          mappingFn = (NodeAttrs attrs, Scope scope, Object controller, FilterMap filters) {
            if (attrs[attrName] == null) return;
            Expression attrExprFn = _parser(attrs[attrName]);
            var shadowValue = null;
            scope.watch(_astParser(attrs[attrName], filters: filters),
                    (v, _) => dstPathFn.assign(controller, shadowValue = v));
          };
          break;
        case '=>!':
          mappingFn = (NodeAttrs attrs, Scope scope, Object controller, FilterMap filters) {
            if (attrs[attrName] == null) return;
            Expression attrExprFn = _parser(attrs[attrName]);
            var watch;
            watch = scope.watch(
                _astParser(attrs[attrName], filters: filters),
                (value, _) {
                  if (dstPathFn.assign(controller, value) != null) {
                    watch.remove();
                  }
                });
          };
          break;
        case '&':
          mappingFn = (NodeAttrs attrs, Scope scope, Object dst, FilterMap filters) {
            dstPathFn.assign(dst, _parser(attrs[attrName]).bind(scope.context, ScopeLocals.wrapper));
          };
          break;
      }
      ref.mappings.add(mappingFn);
    });
  }
}

