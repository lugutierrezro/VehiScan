from kedro.pipeline import Pipeline, node, pipeline
from .nodes import download_sample_video, track_vehicles

def create_pipeline(**kwargs) -> Pipeline:
    return pipeline(
        [
            node(
                func=download_sample_video,
                inputs=["params:sample_video_url", "params:video_path"],
                outputs="downloaded_video_path",
                name="download_sample_video_node",
            ),
            node(
                func=track_vehicles,
                inputs=[
                    "downloaded_video_path",
                    "params:model_name",
                    "params:tracker_type",
                    "params:output_video_path",
                    "params:crops_dir",
                ],
                outputs="tracked_vehicles_meta",
                name="track_vehicles_node",
            ),
        ]
    )
