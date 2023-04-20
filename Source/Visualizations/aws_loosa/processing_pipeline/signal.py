# -*- coding: utf-8 -*-
"""
A signal/slot implementation

File:    signal.py
Author:  Thiago Marcos P. Santos
Author:  Christopher S. Case
Author:  David H. Bronke
Created: August 28, 2008
Updated: December 12, 2011
License: MIT
Source: http://code.activestate.com/recipes/577980-improved-signalsslots-implementation-in-python/
"""
import inspect
import threading
from weakref import WeakSet, WeakKeyDictionary


class Signal(object):
    def __init__(self):
        self._func_threads = []
        self._method_threads = []
        self._functions = WeakSet()
        self._methods = WeakKeyDictionary()
        self._id_to_functions_mapping = {}
        self._id_to_methods_mapping = {}

    def __call__(self, *args, **kwargs):
        functions = []
        methods = {}

        identifier = kwargs.pop('identifier', None)

        if identifier:
            if identifier in self._id_to_functions_mapping:
                functions = self._id_to_functions_mapping[identifier]
            if identifier in self._id_to_methods_mapping:
                methods = self._id_to_methods_mapping[identifier]
        else:
            functions = self._functions
            methods = self._methods

        # Call handler functions
        for func in functions:
            # Execute func on a separate thread
            thread = threading.Thread(target=func, args=args, kwargs=kwargs)
            self._func_threads.append(thread)
            thread.daemon = True
            thread.start()

        # Call handler methods
        for obj, funcs in list(methods.items()):
            for func in funcs:
                # Prepend "self" to arguments list
                arguments = [obj] + [a for a in args]

                # Execute func on a separate thread
                thread = threading.Thread(target=func, args=arguments, kwargs=kwargs)
                self._method_threads.append(thread)
                thread.daemon = True
                thread.start()

    def connect(self, slot, identifier=None):
        if inspect.ismethod(slot):
            if slot.__self__ not in self._methods:
                self._methods[slot.__self__] = WeakSet()

            self._methods[slot.__self__].add(slot.__func__)

        else:
            self._functions.add(slot)

        if identifier:
            if inspect.ismethod(slot):
                if identifier not in self._id_to_methods_mapping:
                    self._id_to_methods_mapping[identifier] = WeakKeyDictionary()

                if slot.__self__ not in self._id_to_methods_mapping[identifier]:
                    self._id_to_methods_mapping[identifier][slot.__self__] = set()

                self._id_to_methods_mapping[identifier][slot.__self__].add(slot.__func__)
            else:
                if identifier not in self._id_to_functions_mapping:
                    self._id_to_functions_mapping[identifier] = WeakSet()

                self._id_to_functions_mapping[identifier].add(slot)
