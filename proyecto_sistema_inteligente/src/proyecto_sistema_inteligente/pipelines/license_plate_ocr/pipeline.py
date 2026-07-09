from kedro.pipeline import Pipeline, node, pipeline
from .nodes import detect_and_ocr_plates

def create_pipeline(**kwargs) -> Pipeline:
    return pipeline(
        [
            node(
                func=detect_and_ocr_plates,
                inputs=[
                    "tracked_vehicles_meta",
                    "params:ocr_languages",
                    "params:output_ocr_path",
                ],
                outputs="plate_readings",
                name="detect_and_ocr_plates_node",
            )
        ]
    )
