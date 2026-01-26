def dynamic_object_from_json(data):
    try:
        import iris
    except Exception as exc:
        raise RuntimeError("iris is not available") from exc
    return iris.cls("%DynamicObject")._FromJSON(data)
