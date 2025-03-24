#!/usr/bin/env python3
"""
Code Structure Extractor CLI

Extract code structure from Python files and convert to different formats using adapters.
"""

import argparse
import ast
import fnmatch
import json
import os
import sys
from abc import ABC, abstractmethod
from typing import Dict, List, Any

# System prompt to be used with IDL output
SYSTEM_PROMPT = """System Prompt:
You are an expert Python programmer analyzing code files that include both
IDL (Interface Definition Language) declarations and Python implementations.
In these concatenated files, IDL declarations serve as interfaces or traits with type information,
 while the Python code contains the actual implementations.

When analyzing, use the IDL declarations as a guide to understand the intended design,
but focus primarily on the Python code. Your analysis should cover the overall purpose, module architecture,
key functions, and notable design decisions.
Emphasize practical insights that help developers understand and work with the code.

Key Points:

- Treat IDL declarations (with keywords like "function", "in", "returns", and "const") as Python interfaces 
  with type hints.
- Focus on the actual Python implementations for detailed analysis.
- Provide an analysis that is structured yet adaptable to various files and user-specific prompts.

"""


class ASTExtractor:
    """Base AST extractor to parse Python code and extract structure"""

    def extract_code_structure(self, code: str) -> Dict[str, Any]:
        """Extract the structure of Python code."""
        tree = ast.parse(code)

        # Add depth information to track scope
        for depth, node in self._walk_tree_with_depth(tree):
            node._depth = depth

        extractor = CodeStructureExtractor()
        extractor.visit(tree)

        module_docstring = ast.get_docstring(tree)
        if module_docstring:
            extractor.structure["module_docstring"] = module_docstring

        return extractor.structure

    def _walk_tree_with_depth(self, node, depth=0):
        """Walk the AST tree and yield each node with its depth."""
        yield depth, node
        for child in ast.iter_child_nodes(node):
            yield from self._walk_tree_with_depth(child, depth + 1)


class FormatAdapter(ABC):
    """Base adapter interface for different output formats"""

    @abstractmethod
    def convert(self, structure: Dict[str, Any]) -> str:
        """Convert the extracted structure to the target format"""
        pass


class IDLAdapter(FormatAdapter):
    """Adapter for IDL format output"""

    def convert(self, structure: Dict[str, Any]) -> str:
        """Generate IDL-like syntax from code structure."""
        lines = []

        # Add module docstring
        if "module_docstring" in structure:
            for line in structure["module_docstring"].split('\n'):
                lines.append(f"// {line.strip()}")
            lines.append("")

        # Add imports
        for imp in structure.get("imports", []):
            if imp["type"] == "import":
                if imp["alias"]:
                    lines.append(f"import {imp['name']} as {imp['alias']};")
                else:
                    lines.append(f"import {imp['name']};")
            else:  # import_from
                name_part = imp["name"]
                if imp["alias"]:
                    name_part += f" as {imp['alias']}"
                lines.append(f"import {imp['module']}.{name_part};")

        if structure.get("imports", []):
            lines.append("")

        # Add global variables
        for var in structure.get("global_vars", []):
            value_repr = repr(var["value"]) if var["value"] is not None else "undefined"
            if value_repr.startswith("'<") and value_repr.endswith(">'"):
                # Clean up special representations
                value_repr = value_repr[1:-1]  # Remove quotes
            lines.append(f"const {var['name']} = {value_repr};")

        if structure.get("global_vars", []):
            lines.append("")

        # Add functions
        for func in structure.get("functions", []):
            # Add docstring as comment
            if func.get("docstring"):
                for line in func["docstring"].split('\n'):
                    lines.append(f"// {line.strip()}")

            # Indicate if function is async
            if func.get("is_async", False):
                lines.append(f"// This is an async function")

            # Handle decorators with special treatment for routers
            for decorator in func.get("decorators", []):
                decorator_str = str(decorator)

                # Convert router decorators to a cleaner Route annotation
                if "router." in decorator_str:
                    http_method = ""
                    path = ""
                    tags = []

                    # Determine HTTP method
                    if "get(" in decorator_str.lower():
                        http_method = "GET"
                    elif "post(" in decorator_str.lower():
                        http_method = "POST"
                    elif "put(" in decorator_str.lower():
                        http_method = "PUT"
                    elif "delete(" in decorator_str.lower():
                        http_method = "DELETE"
                    elif "patch(" in decorator_str.lower():
                        http_method = "PATCH"

                    # Extract path and tags - simple parsing from the decorator string
                    if "(" in decorator_str and ")" in decorator_str:
                        args_str = decorator_str.split("(", 1)[1].rsplit(")", 1)[0]
                        args_parts = args_str.split(",")

                        # First argument is typically the path
                        if args_parts and ('"' in args_parts[0] or "'" in args_parts[0]):
                            path = args_parts[0].strip().strip('"\'')

                        # Look for tags
                        for part in args_parts:
                            if "tags=" in part:
                                tags_str = part.split("tags=", 1)[1].strip()
                                if tags_str.startswith("[") and "]" in tags_str:
                                    tags_content = tags_str.split("[", 1)[1].split("]")[0]
                                    tags = [t.strip().strip('"\'') for t in tags_content.split(",") if t.strip()]

                    if http_method and path:
                        if tags:
                            lines.append(f"@Route(method={http_method}, path=\"{path}\", tags={tags})")
                        else:
                            lines.append(f"@Route(method={http_method}, path=\"{path}\")")
                    else:
                        lines.append(f"@{decorator}")
                else:
                    lines.append(f"@{decorator}")

            # Create function signature
            params_str = []
            for param in func.get("params", []):
                param_str = f"in "
                if "type" in param and param["type"]:
                    param_str += f"{param['type']} "
                param_str += param["name"]
                params_str.append(param_str)

            return_type = func.get("return_type", "void")

            lines.append(f"function {func['name']}({', '.join(params_str)}) returns {return_type};")
            lines.append("")

        # Add classes
        for cls in structure.get("classes", []):
            # Add inheritance
            extends_clause = ""
            if cls["bases"]:
                extends_clause = f" extends {', '.join(cls['bases'])}"

            lines.append(f"interface {cls['name']}{extends_clause} {{")

            # Add class docstring
            if cls.get("docstring"):
                for line in cls["docstring"].split('\n'):
                    lines.append(f"  // {line.strip()}")
                lines.append("")

            # Add class variables
            for var in cls.get("class_vars", []):
                if var["value"] is not None:
                    lines.append(f"  const {var['name']} = {repr(var['value'])};")
                else:
                    lines.append(f"  const {var['name']} = undefined;")

            if cls.get("class_vars"):
                lines.append("")

            # Add constructor if present
            init_method = next((m for m in cls.get("methods", []) if m["name"] == "__init__"), None)
            if init_method:
                params_str = []
                for param in init_method.get("params", [])[1:]:  # Skip self
                    param_str = ""
                    if "type" in param and param["type"]:
                        param_str += f"{param['type']} "
                    param_str += param["name"]
                    params_str.append(param_str)

                lines.append(f"  constructor({', '.join(params_str)});")

                if init_method.get("docstring"):
                    lines[-1] = lines[-1] + "  // " + init_method["docstring"].split('\n')[0]

                lines.append("")

            # Add methods (excluding __init__)
            for method in [m for m in cls.get("methods", []) if m["name"] != "__init__"]:
                # Add method docstring as comment
                if method.get("docstring"):
                    for line in method["docstring"].split('\n'):
                        lines.append(f"  // {line.strip()}")

                # Indicate if method is async
                if method.get("is_async", False):
                    lines.append(f"  // This is an async method")

                # Add decorators as annotations
                for decorator in method.get("decorators", []):
                    lines.append(f"  @{decorator}")

                # Create method signature
                params_str = []
                is_static = "staticmethod" in method.get("decorators", [])
                method_params = method.get("params", [])

                # Skip 'self' for instance methods
                if not is_static and method_params and method_params[0]["name"] == "self":
                    method_params = method_params[1:]

                for param in method_params:
                    param_str = f"in "
                    if "type" in param and param["type"]:
                        param_str += f"{param['type']} "
                    param_str += param["name"]
                    params_str.append(param_str)

                return_type = method.get("return_type", "void")

                if is_static:
                    lines.append(f"  static {method['name']}({', '.join(params_str)}) returns {return_type};")
                else:
                    lines.append(f"  {method['name']}({', '.join(params_str)}) returns {return_type};")

                lines.append("")

            lines.append("};")
            lines.append("")

        return "\n".join(lines)


class JSONAdapter(FormatAdapter):
    """Adapter for JSON format output"""

    def convert(self, structure: Dict[str, Any]) -> str:
        """Convert the extracted structure to JSON format"""
        return json.dumps(structure, indent=2)

    @staticmethod
    def convert_list(structures: List[Dict[str, Any]]) -> str:
        """Convert a list of structures to JSON format"""
        return json.dumps(structures, indent=2)


class CodeStructureExtractor(ast.NodeVisitor):
    """Extract structural information from Python code"""

    def __init__(self):
        self.structure = {
            "imports": [],
            "global_vars": [],
            "functions": [],
            "classes": [],
        }
        self.current_class = None

    def visit_Import(self, node):
        for name in node.names:
            self.structure["imports"].append({
                "type": "import",
                "name": name.name,
                "alias": name.asname
            })
        self.generic_visit(node)

    def visit_ImportFrom(self, node):
        for name in node.names:
            self.structure["imports"].append({
                "type": "import_from",
                "module": node.module,
                "name": name.name,
                "alias": name.asname
            })
        self.generic_visit(node)

    def visit_Assign(self, node):
        # Only capture assignments at module level, not inside functions or methods
        if not self.current_class and isinstance(node, ast.Assign):
            # Get the scope depth to ensure we're at module level
            scope_depth = getattr(node, '_depth', 0)
            if scope_depth == 0:  # Module level
                for target in node.targets:
                    if isinstance(target, ast.Name):
                        # Attempt to get actual value
                        value = self._extract_value(node.value)

                        # Check if this variable name already exists to avoid duplication
                        if not any(var["name"] == target.id for var in self.structure["global_vars"]):
                            self.structure["global_vars"].append({
                                "name": target.id,
                                "value": value
                            })
        self.generic_visit(node)

    def _extract_value(self, node):
        """Extract the actual value from an AST node if possible."""
        if isinstance(node, ast.Constant):
            return node.value
        elif isinstance(node, ast.List):
            return [self._extract_value(item) for item in node.elts]
        elif isinstance(node, ast.Dict):
            keys = [self._extract_value(k) for k in node.keys]
            values = [self._extract_value(v) for v in node.values]
            return dict(zip(keys, values))
        elif isinstance(node, ast.Tuple):
            return tuple(self._extract_value(item) for item in node.elts)
        elif isinstance(node, ast.Name):
            return f"<{node.id}>"  # Reference to another variable
        elif isinstance(node, ast.Call):
            return f"<function call>"
        return "<complex value>"

    def _process_function(self, node, is_async=False):
        """Process function definition nodes"""
        docstring = ast.get_docstring(node)

        params = []
        for arg in node.args.args:
            param = {"name": arg.arg}
            if arg.annotation:
                if isinstance(arg.annotation, ast.Name):
                    param["type"] = arg.annotation.id
                elif isinstance(arg.annotation, ast.Subscript):
                    param["type"] = self._get_annotation_str(arg.annotation)
            params.append(param)

        if node.args.vararg:
            params.append({
                "name": f"*{node.args.vararg.arg}",
                "type": self._get_annotation_str(node.args.vararg.annotation) if node.args.vararg.annotation else None
            })

        if node.args.kwarg:
            params.append({
                "name": f"**{node.args.kwarg.arg}",
                "type": self._get_annotation_str(node.args.kwarg.annotation) if node.args.kwarg.annotation else None
            })

        return_type = None
        if node.returns:
            if isinstance(node.returns, ast.Name):
                return_type = node.returns.id
            else:
                return_type = self._get_annotation_str(node.returns)

        function_data = {
            "name": node.name,
            "params": params,
            "docstring": docstring,
            "return_type": return_type,
            "decorators": [self._get_decorator_str(d) for d in node.decorator_list],
            "is_async": is_async
        }

        if self.current_class:
            self.current_class["methods"].append(function_data)
        else:
            self.structure["functions"].append(function_data)

        self.generic_visit(node)

    def visit_FunctionDef(self, node):
        """Handle regular function definitions"""
        self._process_function(node, is_async=False)

    def visit_AsyncFunctionDef(self, node):
        """Handle async function definitions"""
        self._process_function(node, is_async=True)

    def visit_ClassDef(self, node):
        docstring = ast.get_docstring(node)

        bases = []
        for base in node.bases:
            if isinstance(base, ast.Name):
                bases.append(base.id)
            elif isinstance(base, ast.Attribute):
                bases.append(f"{self._get_attribute_path(base)}")

        class_data = {
            "name": node.name,
            "bases": bases,
            "docstring": docstring,
            "methods": [],
            "class_vars": []
        }

        old_class = self.current_class
        self.current_class = class_data

        for child in node.body:
            if isinstance(child, ast.Assign):
                for target in child.targets:
                    if isinstance(target, ast.Name):
                        value = None
                        if isinstance(child.value, ast.Constant):
                            value = child.value.value
                        class_data["class_vars"].append({
                            "name": target.id,
                            "value": value
                        })
            else:
                self.visit(child)

        self.current_class = old_class
        self.structure["classes"].append(class_data)

    def _get_annotation_str(self, node) -> str:
        """Extract a string representation of a type annotation from an AST node.
        Handles Python 3.8 and 3.9+ compatibility differences in AST structure.
        """
        if node is None:
            return "Any"

        # noinspection PyDeprecation
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Subscript):
            value = self._get_annotation_str(node.value)

            # Handle slice differently based on Python version
            slice_value = "Any"

            # Python 3.9+ has direct values in node.slice
            if hasattr(node, 'slice'):
                if isinstance(node.slice, ast.Index):  # Python 3.8
                    if hasattr(node.slice, 'value'):
                        slice_value = self._get_annotation_str(node.slice.value)
                elif isinstance(node.slice, ast.Tuple):  # Python 3.9+
                    slice_value = ", ".join(self._get_annotation_str(elt) for elt in node.slice.elts)
                elif isinstance(node.slice, ast.Name):  # Python 3.9+
                    slice_value = node.slice.id
                elif isinstance(node.slice, ast.Constant):  # Python 3.9+
                    slice_value = str(node.slice.value)
                elif hasattr(node.slice, '__dict__'):  # Last resort, try direct conversion
                    try:
                        slice_value = str(ast.unparse(node.slice))
                    except (AttributeError, ValueError):
                        slice_value = "Any"

            return f"{value}[{slice_value}]"
        elif isinstance(node, ast.Tuple):
            return ", ".join(self._get_annotation_str(elt) for elt in node.elts)
        elif isinstance(node, ast.Attribute):
            return self._get_attribute_path(node)
        elif isinstance(node, ast.Constant):
            return str(node.value)
        elif isinstance(node, ast.Str):  # For backward compatibility with Python < 3.8
            return str(node.s)
        elif hasattr(node, 'id'):  # Handle any node with an 'id' attribute
            return node.id
        else:
            try:
                # For newer Python versions, attempt to use ast.unparse
                return ast.unparse(node)
            except (AttributeError, ValueError):
                # ast.unparse is not available or failed
                return "Any"

    def _get_attribute_path(self, node) -> str:
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Attribute):
            return f"{self._get_attribute_path(node.value)}.{node.attr}"
        return "unknown"

    def _get_decorator_str(self, node) -> str:
        """Extract decorator name and arguments in a more detailed way"""
        if isinstance(node, ast.Name):
            return node.id
        elif isinstance(node, ast.Call):
            func_name = self._get_attribute_path(node.func)
            args = []

            # Handle positional arguments
            for arg in node.args:
                if isinstance(arg, ast.Constant):
                    args.append(repr(arg.value))
                elif isinstance(arg, ast.Name):
                    args.append(arg.id)
                elif isinstance(arg, ast.Attribute):
                    args.append(self._get_attribute_path(arg))
                elif isinstance(arg, ast.List):
                    # Handle list arguments
                    list_items = []
                    for item in arg.elts:
                        if isinstance(item, ast.Constant):
                            list_items.append(repr(item.value))
                        else:
                            list_items.append("...")
                    args.append(f"[{', '.join(list_items)}]")
                else:
                    args.append("...")

            # Handle keyword arguments
            for kw in node.keywords:
                kw_value = None
                if isinstance(kw.value, ast.Constant):
                    kw_value = repr(kw.value.value)
                elif isinstance(kw.value, ast.Name):
                    kw_value = kw.value.id
                elif isinstance(kw.value, ast.Call):
                    kw_value = f"{self._get_attribute_path(kw.value.func)}(...)"
                elif isinstance(kw.value, ast.List):
                    list_items = []
                    for item in kw.value.elts:
                        if isinstance(item, ast.Constant):
                            list_items.append(repr(item.value))
                        else:
                            list_items.append("...")
                    kw_value = f"[{', '.join(list_items)}]"
                else:
                    kw_value = "..."

                args.append(f"{kw.arg}={kw_value}")

            return f"{func_name}({', '.join(args)})"
        elif isinstance(node, ast.Attribute):
            return self._get_attribute_path(node)
        return "unknown_decorator"


class CodeProcessorFactory:
    """Factory for creating format-specific processors"""

    @staticmethod
    def create_adapter(format_type: str) -> FormatAdapter:
        """Create and return the appropriate adapter for the given format"""
        if format_type == "idl":
            return IDLAdapter()
        elif format_type == "json":
            return JSONAdapter()
        else:
            raise ValueError(f"Unsupported format type: {format_type}")


def process_file(file_path: str) -> Dict[str, Any]:
    """Process a single Python file."""
    with open(file_path, 'r', encoding='utf-8') as f:
        code = f.read()

    extractor = ASTExtractor()
    structure = extractor.extract_code_structure(code)
    structure['file_path'] = file_path

    return structure


def process_directory(directory: str, exclude_patterns: List[str], output_format: str) -> List[Dict[str, Any]]:
    """Process all Python files in a directory recursively."""
    results = []

    for root, _, files in os.walk(directory):
        for file in files:
            if not file.endswith('.py'):
                continue

            file_path = os.path.join(root, file)

            # Check if file should be excluded
            excluded = False
            for pattern in exclude_patterns:
                if fnmatch.fnmatch(file_path, pattern):
                    excluded = True
                    break

            if excluded:
                continue

            try:
                structure = process_file(file_path)
                results.append(structure)
            except Exception as e:
                print(f"Error processing {file_path}: {str(e)}", file=sys.stderr)

    return results


def transform_content(content: str, transform_type: str) -> str:
    """
    Transform the content based on the specified transform type.

    Args:
        content (str): The content to transform.
        transform_type (str): The type of transformation to apply.

    Returns:
        str: The transformed content.
    """
    if transform_type in ["idl", "json"]:
        extractor = ASTExtractor()
        structure = extractor.extract_code_structure(content)
        adapter = CodeProcessorFactory.create_adapter(transform_type)
        return adapter.convert(structure)
    else:
        # Return the content unchanged for unknown transform types
        return content


def main():
    """CLI entry point"""
    parser = argparse.ArgumentParser(description='Extract code structure from Python files')
    parser.add_argument('path', help='File or directory to process')
    parser.add_argument('--format', choices=['json', 'idl'], default='idl',
                        help='Output format (default: idl)')
    parser.add_argument('--output', '-o', help='Output file (default: stdout)')
    parser.add_argument('--exclude', '-e', action='append', default=[],
                        help='Exclude patterns (can be specified multiple times)')
    parser.add_argument('--include-prompt', action='store_true',
                        help='Include system prompt with IDL output')

    args = parser.parse_args()

    # Process input path
    if os.path.isfile(args.path):
        structures = [process_file(args.path)]
    elif os.path.isdir(args.path):
        structures = process_directory(args.path, args.exclude, args.format)
    else:
        print(f"Error: {args.path} is not a valid file or directory", file=sys.stderr)
        sys.exit(1)

    # Generate output using the adapter pattern
    if args.format == 'json':
        adapter = JSONAdapter()
        # Use convert_list for a list of structures
        output = adapter.convert_list(structures)
    else:  # idl
        output = SYSTEM_PROMPT if args.include_prompt else ""
        adapter = IDLAdapter()
        for structure in structures:
            file_path = structure.pop('file_path')
            if output:  # Add a newline if we already have content
                output += "\n\n"
            output += f"// File: {file_path}\n"
            output += adapter.convert(structure)
            output += f"\n// End of {file_path}\n"

    # Write output
    if args.output:
        with open(args.output, 'w', encoding='utf-8') as f:
            f.write(output)
    else:
        print(output)


if __name__ == "__main__":
    main()
