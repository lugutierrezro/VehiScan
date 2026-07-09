from kedro.pipeline import Pipeline, node, pipeline
from .nodes import extract_vehicle_embeddings

def create_pipeline(**kwargs) -> Pipeline:
    return pipeline(
        [
            node(
                func=extract_vehicle_embeddings,
                inputs=[
                    "tracked_vehicles_meta",
                    "params:output_reid_path",
                ],
                outputs="reid_embeddings",
                name="extract_vehicle_embeddings_node",
            )
        ]
    )
