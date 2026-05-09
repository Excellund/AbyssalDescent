extends Node
## Service for replicating enemy state across multiplayer peers.
## Owns enemy node registry, target position/facing dictionaries, damage attribution,
## and the RPC surface for enemy spawn/state/death sync.
##
## Phase 4 extraction is incremental — this skeleton is intentionally empty.
## State and behavior migrate in subsequent steps (T2-T6) so each commit is small,
## reversible, and behavior-preserving. world_generator continues to own the live
## enemy state until T2 moves it here.

var world_generator: Node = null


## Bind the active world generator. Called by world_generator on _ready and cleared
## on tree exit so the service does not retain a stale reference between runs.
func bind_world(world: Node) -> void:
	world_generator = world


func unbind_world(world: Node) -> void:
	if world_generator == world:
		world_generator = null
