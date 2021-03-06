library angular.dom.element_binder_spec;

import '../_specs.dart';
import 'dart:mirrors';

@Component(selector:'component')            class _Component{}
@Decorator(selector:'[ignore-children]',
             children: Directive.IGNORE_CHILDREN)
                                              class _IgnoreChildren{}
@Decorator(selector:'[structural]',
             children: Directive.TRANSCLUDE_CHILDREN)
                                              class _Structural{}
@Decorator(selector:'[directive]')          class _DirectiveAttr{}


directiveFor(i) {
  ClassMirror cm = reflectType(i);

}
main() => describe('ElementBinderBuilder', () {
  var b;
  var directives;
  var node = null;

  beforeEachModule((Module module) {
    module
      ..bind(_DirectiveAttr)
      ..bind(_Component)
      ..bind(_IgnoreChildren)
      ..bind(_Structural);
  });

  beforeEach((DirectiveMap d, ElementBinderFactory f, Injector i) {
    directives = d;
    b = f.builder(null, null, i);
  });

  addDirective(selector) {
    directives.forEach((Directive annotation, Type type) {
      if (annotation.selector == selector)
        b.addDirective(new DirectiveRef(node, type, annotation, new Key(type), null));
    });
    b = b.binder;
  }

  it('should add a decorator', () {
    expect(b.decorators.length).toEqual(0);

    addDirective('[directive]');

    expect(b.decorators.length).toEqual(1);
    expect(b.componentData).toBeNull();
    expect(b.childMode).toEqual(Directive.COMPILE_CHILDREN);

  });

  it('should add a component', async(() {
    addDirective('component');

    expect(b.decorators.length).toEqual(0);
    expect(b.componentData).toBeNotNull();
  }));

  it('should add a template', () {
    addDirective('[structural]');

    expect(b.template).toBeNotNull();
  });

  it('should add a directive that ignores children', () {
    addDirective('[ignore-children]');

    expect(b.decorators.length).toEqual(1);
    expect(b.componentData).toBeNull();
    expect(b.childMode).toEqual(Directive.IGNORE_CHILDREN);
  });
});
