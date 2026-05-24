/* Source: /tmp/jac-spike-build/main.jac */
import {__jacJsx, __jacSpawn} from "@jac/runtime";
let API_LABEL = "Runtime Test";
class ButtonProps {
  constructor(props = {}) {
    this.label = (props.hasOwnProperty("label") ? props.label : "Tap Me");
    this.color = (props.hasOwnProperty("color") ? props.color : "primary");
  }
}
function app() {
  let props = new ButtonProps({label: "Tap Me", color: "primary"});
  return __jacJsx("div", {"class": "app"}, [__jacJsx("h1", {}, [API_LABEL]), __jacJsx("button", {"class": props.color, "data-id": "button"}, [props.label])]);
}
//# sourceMappingURL=main.js.map
