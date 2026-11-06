components {
  id: "app"
  component: "/main/app.script"
}
components {
  id: "home"
  component: "/screens/home.gui"
}
components {
  id: "training"
  component: "/screens/training.gui"
}
components {
  id: "end"
  component: "/screens/end.gui"
}
components {
  id: "keys"
  component: "/screens/keys.gui"
}
components {
  id: "multi"
  component: "/screens/multi.gui"
}
components {
  id: "room"
  component: "/screens/room.gui"
}
components {
  id: "probe"
  component: "/screens/probe.gui"
}
components {
  id: "rotate"
  component: "/screens/rotate.gui"
}
components {
  id: "intro"
  component: "/screens/intro.gui"
}
embedded_components {
  id: "game_proxy"
  type: "collectionproxy"
  data: "collection: \"/game/game.collection\"\n"
  ""
}
embedded_components {
  id: "menu_proxy"
  type: "collectionproxy"
  data: "collection: \"/menu/menu.collection\"\n"
  ""
}
