components {
  id: "script"
  component: "/main/world.script"
}
embedded_components {
  id: "chunk_factory"
  type: "factory"
  data: "prototype: \"/main/chunk.go\"\n"
  ""
}
embedded_components {
  id: "blob_factory"
  type: "factory"
  data: "prototype: \"/main/blob.go\"\n"
  ""
}
embedded_components {
  id: "ball_factory"
  type: "factory"
  data: "prototype: \"/main/ball.go\"\n"
  ""
}
