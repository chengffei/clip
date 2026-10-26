"""Convert PP-OCRv6 small (RapidOCR's ONNX exports) to Core ML for Clip.

Python 3.12 with: rapidocr==3.10.0 onnxruntime onnx onnx2torch==1.5.15
torch==2.7.0 coremltools==9.0. Run once with RapidOCR so it downloads the
models, then:  python convert.py <rapidocr models dir> <out dir>
Then: xcrun coremlcompiler compile <out>/PPOCRv6{Det,Rec}.mlpackage Resources/OCRModels
"""
import sys
import numpy as np
import onnx
import onnxruntime as ort
import torch
import coremltools as ct
from onnx import helper, numpy_helper
from onnx2torch import convert

src, out = sys.argv[1].rstrip("/") + "/", sys.argv[2].rstrip("/") + "/"


def fix(name):
    m = onnx.load(src + name)
    for n in m.graph.node:
        for a in list(n.attribute):
            # onnx2torch lacks SAME_UPPER; all uses are stride 1, kernel 2,
            # so the padding is a constant one pixel at the end.
            if a.name == "auto_pad" and a.s == b"SAME_UPPER":
                k = [x for x in n.attribute if x.name == "kernel_shape"][0].ints
                assert list([x for x in n.attribute if x.name == "strides"][0].ints) == [1, 1]
                n.attribute.remove(a)
                n.attribute.extend([helper.make_attribute("pads", [(k[0] - 1) // 2, (k[1] - 1) // 2, (k[0] - 1) - (k[0] - 1) // 2, (k[1] - 1) - (k[1] - 1) // 2])])
        # The recognizer computes one reshape target from the input width;
        # tracing would freeze it, so express it with -1 instead.
        if n.op_type == "Reshape" and n.name == "Reshape.73":
            m.graph.initializer.append(numpy_helper.from_array(np.array([0, 1, -1, 120], dtype=np.int64), "reshape73_shape"))
            n.input[1] = "reshape73_shape"
    path = out + name.replace(".onnx", "_fixed.onnx")
    onnx.save(m, path)
    return path


for key, name, example, shape, check in [
    ("Det", "PP-OCRv6_det_small.onnx", (1, 3, 128, 320),
     ct.Shape(shape=(1, 3, ct.RangeDim(32, 4096, default=736), ct.RangeDim(32, 4096, default=736))), (1, 3, 736, 1024)),
    ("Rec", "PP-OCRv6_rec_small.onnx", (1, 3, 48, 320),
     ct.Shape(shape=(1, 3, 48, ct.RangeDim(16, 4096, default=320))), (1, 3, 48, 1800)),
]:
    fixed = fix(name)
    traced = torch.jit.trace(convert(onnx.load(fixed)).eval(), torch.rand(*example))
    ml = ct.convert(traced, inputs=[ct.TensorType(name="x", shape=shape)], outputs=[ct.TensorType(name="y")],
                    minimum_deployment_target=ct.target.macOS14, compute_precision=ct.precision.FLOAT16,
                    convert_to="mlprogram")
    ml.save(out + f"PPOCRv6{key}.mlpackage")
    x = np.random.rand(*check).astype(np.float32) * 2 - 1
    ref = ort.InferenceSession(src + name).run(None, {"x": x})[0]
    y = ct.models.MLModel(out + f"PPOCRv6{key}.mlpackage", compute_units=ct.ComputeUnit.CPU_AND_NE).predict({"x": x})["y"]
    note = f" argmax agreement {np.mean(ref.argmax(-1) == y.argmax(-1)):.4f}" if key == "Rec" else ""
    print(key, "max abs diff vs ONNX", float(np.abs(y - ref).max()), note)

keys = ort.InferenceSession(src + "PP-OCRv6_rec_small.onnx").get_modelmeta().custom_metadata_map["character"]
open(out + "ppocrv6_keys.txt", "w", encoding="utf-8").write(keys)
