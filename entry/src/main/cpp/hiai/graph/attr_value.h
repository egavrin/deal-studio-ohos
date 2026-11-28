// Vendored (trimmed) from the public HiAI DDK reference
// (github.com/946166920/hiai_ddk, Apache-2.0): only the AttrValue::ValueType
// enum the attribute-definition interface needs.
#ifndef VENDORED_HIAI_GRAPH_ATTR_VALUE_H
#define VENDORED_HIAI_GRAPH_ATTR_VALUE_H
#include <cstdint>
#include <string>
#include <vector>
namespace ge {
class AttrValue {
public:
enum ValueType {
        VT_NONE = 0,
        VT_STRING,
        VT_FLOAT,
        VT_BOOL,
        VT_INT,
        VT_TENSOR_DESC,
        VT_TENSOR,
        VT_BYTES,
        VT_GRAPH,
        VT_NAMED_ATTRS,

        VT_LIST_BASE = 1000,
        VT_LIST_STRING = VT_LIST_BASE + VT_STRING,
        VT_LIST_FLOAT = VT_LIST_BASE + VT_FLOAT,
        VT_LIST_BOOL = VT_LIST_BASE + VT_BOOL,
        VT_LIST_INT = VT_LIST_BASE + VT_INT,
        VT_LIST_TENSOR_DESC = VT_LIST_BASE + VT_TENSOR_DESC,
        VT_LIST_TENSOR = VT_LIST_BASE + VT_TENSOR,
        VT_LIST_BYTES = VT_LIST_BASE + VT_BYTES,
        VT_LIST_GRAPH = VT_LIST_BASE + VT_GRAPH,
        VT_LIST_NAMED_ATTRS = VT_LIST_BASE + VT_NAMED_ATTRS,
    };
};
} // namespace ge
#endif
