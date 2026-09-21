// GENERATED FILE - DO NOT EDIT.

import 'overlay_widget_catalog.dart';

const generatedOverlayWidgets = <GeneratedOverlayWidget>[
  GeneratedOverlayWidget(
    pluginId: "heartrate",
    id: "heartRate",
    name: "Heart Rate",
    description: "Displays the live Heart Rate state from ShowRunner.",
    icon: "mdi mdi-heart-pulse",
    capabilities: {
      "states": ["heartRate", "connection", "device"],
      "resizable": true,
    },
    defaultSize: {"width": 260, "height": 110},
    config: {
      "showLabel": {"type": "boolean", "default": true},
      "accentColor": {"type": "string", "default": "#f43f5e"},
      "animate": {"type": "boolean", "default": true},
      "showBattery": {"type": "boolean", "default": false},
      "showConnection": {"type": "boolean", "default": true},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "heartrate",
    id: "heartRateGraph",
    name: "Heart Rate Graph",
    description: "Displays a live, bounded heart-rate history.",
    icon: "mdi mdi-chart-line",
    capabilities: {
      "states": ["heartRate", "connection"],
      "resizable": true,
    },
    defaultSize: {"width": 420, "height": 180},
    config: {
      "showLabel": {"type": "boolean", "default": true},
      "accentColor": {"type": "string", "default": "#f43f5e"},
      "maxBpm": {"type": "number", "default": 200},
      "showConnection": {"type": "boolean", "default": true},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "heartrate",
    id: "heartRateZone",
    name: "Heart Rate Zone",
    description: "Displays the current heart-rate training zone.",
    icon: "mdi mdi-heart-pulse",
    capabilities: {
      "states": ["zone", "connection"],
      "resizable": true,
    },
    defaultSize: {"width": 280, "height": 90},
    config: {
      "showLabel": {"type": "boolean", "default": true},
      "accentColor": {"type": "string", "default": "#f43f5e"},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "alert",
    name: "Alert",
    description: "A classic alert box with text, images, GIFs, and videos.",
    icon: "mdi mdi-alert-box-outline",
    capabilities: {
      "commands": ["showAlert"],
    },
    defaultSize: {"width": 300, "height": 200},
    config: {
      "media": {"type": "array"},
      "transition": {"type": "object"},
      "textBelowMedia": {"type": "boolean", "default": true},
      "title": {"type": "object"},
      "subtitle": {"type": "object"},
      "duration": {"type": "number", "default": 4},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "bar",
    name: "Bar",
    description: "Progress Bar",
    icon: "mdi mdi-square",
    defaultSize: {"width": 400, "height": 90},
    config: {
      "value": {"type": "number", "default": 25, "template": true},
      "target": {"type": "number", "default": 100, "template": true},
      "direction": {
        "type": "string",
        "default": "Right",
        "enum": ["Right", "Left", "Up", "Down"],
      },
      "outerRadius": {
        "type": "object",
        "name": "Outer Corners",
        "default": {},
        "fields": {
          "topLeft": {"type": "number", "name": "Top Left", "default": 0},
          "topRight": {"type": "number", "name": "Top Right", "default": 0},
          "bottomLeft": {"type": "number", "name": "Bottom Left", "default": 0},
          "bottomRight": {
            "type": "number",
            "name": "Bottom Right",
            "default": 0,
          },
        },
      },
      "backgroundStyle": {
        "type": "object",
        "name": "Background Style",
        "default": {"color": "#222222", "elements": []},
        "fields": {
          "color": {"type": "color", "name": "Color", "default": "#222222"},
          "elements": {
            "type": "array",
            "name": "Layers",
            "itemSchema": {
              "type": "object",
              "fields": {
                "image": {"type": "string", "name": "Image"},
                "gradient": {
                  "type": "object",
                  "name": "Gradient",
                  "fields": {
                    "gradientType": {
                      "type": "enum",
                      "name": "Type",
                      "default": "linear",
                      "enum": ["linear", "radial"],
                    },
                    "angle": {"type": "number", "name": "Angle", "default": 0},
                    "stops": {
                      "type": "array",
                      "name": "Stops",
                      "itemSchema": {
                        "type": "object",
                        "fields": {
                          "color": {
                            "type": "color",
                            "name": "Color",
                            "default": "#FFFFFF",
                          },
                          "position": {
                            "type": "number",
                            "name": "Position",
                            "default": 0,
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "outline": {
        "type": "object",
        "name": "Outline",
        "fields": {
          "color": {"type": "color", "name": "Color", "default": "#000000"},
          "style": {
            "type": "enum",
            "name": "Style",
            "default": "solid",
            "enum": ["solid", "dotted", "dashed"],
          },
          "width": {"type": "number", "name": "Width", "default": 10},
        },
      },
      "fillStyle": {
        "type": "object",
        "name": "Fill Style",
        "default": {"color": "#42D392", "elements": []},
        "fields": {
          "color": {"type": "color", "name": "Color", "default": "#42D392"},
          "elements": {
            "type": "array",
            "name": "Layers",
            "itemSchema": {
              "type": "object",
              "fields": {
                "image": {"type": "string", "name": "Image"},
                "gradient": {
                  "type": "object",
                  "name": "Gradient",
                  "fields": {
                    "gradientType": {
                      "type": "enum",
                      "name": "Type",
                      "default": "linear",
                      "enum": ["linear", "radial"],
                    },
                    "angle": {"type": "number", "name": "Angle", "default": 0},
                    "stops": {
                      "type": "array",
                      "name": "Stops",
                      "itemSchema": {
                        "type": "object",
                        "fields": {
                          "color": {
                            "type": "color",
                            "name": "Color",
                            "default": "#FFFFFF",
                          },
                          "position": {
                            "type": "number",
                            "name": "Position",
                            "default": 0,
                          },
                        },
                      },
                    },
                  },
                },
              },
            },
          },
        },
      },
      "fillLine": {
        "type": "object",
        "name": "Fill Line",
        "fields": {
          "color": {"type": "color", "name": "Color", "default": "#000000"},
          "style": {
            "type": "enum",
            "name": "Style",
            "default": "solid",
            "enum": ["solid", "dotted", "dashed"],
          },
          "width": {"type": "number", "name": "Width", "default": 10},
        },
      },
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "chatFeed",
    name: "Chat Feed",
    description:
        "Displays approved chat messages pushed by ShowRunner automations.",
    icon: "mdi mdi-chat-processing-outline",
    capabilities: {
      "events": ["showrunner_chat_message"],
    },
    defaultSize: {"width": 900, "height": 180},
    config: {
      "fontFamily": {"type": "string", "default": "Inter, Arial, sans-serif"},
      "fontSize": {"type": "number", "default": 24},
      "backgroundColor": {"type": "string", "default": "#0d1117"},
      "backgroundOpacity": {"type": "number", "default": 0.72},
      "fadeTime": {"type": "number", "default": 10},
      "maxMessages": {"type": "number", "default": 8},
      "orientation": {
        "type": "string",
        "default": "horizontal",
        "enum": ["horizontal", "vertical"],
      },
      "twitchColor": {"type": "string", "default": "#9146ff"},
      "youtubeColor": {"type": "string", "default": "#ff0033"},
      "showBadges": {"type": "boolean", "default": true},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "emote-bounce",
    name: "Emote Bouncer",
    description: "Bounces Twitch emotes around the overlay.",
    icon: "mdi mdi-emoticon",
    capabilities: {
      "events": ["twitch_message"],
      "commands": ["spawnEmotes"],
    },
    defaultSize: {"width": "canvas", "height": "canvas"},
    config: {
      "lifeTime": {
        "type": "range",
        "default": {"min": 7, "max": 7},
      },
      "emoteSize": {
        "type": "range",
        "default": {"min": 80, "max": 80},
      },
      "velocityMax": {"type": "number", "default": 0.4, "template": true},
      "shakeTime": {"type": "number", "default": 5, "template": true},
      "shakeStrength": {"type": "number", "default": 1, "template": true},
      "gravityXScale": {"type": "number", "default": 0, "template": true},
      "gravityYScale": {"type": "number", "default": 1, "template": true},
      "spamPrevention": {
        "type": "object",
        "name": "Spam Prevention",
        "fields": {
          "emoteRatio": {"type": "number", "name": "Emote Ratio", "default": 1},
          "emoteCap": {"type": "number", "name": "Total Emote Cap"},
          "emoteCapPerMessage": {
            "type": "number",
            "name": "Max Emotes per Chat Message",
          },
        },
      },
      "launchers": {
        "type": "array",
        "name": "Launchers",
        "itemSchema": {
          "type": "object",
          "fields": {
            "x": {"type": "number", "name": "X Position", "default": 0},
            "y": {"type": "number", "name": "Y Position", "default": 0},
            "angle": {"type": "number", "name": "Angle", "default": 0},
            "spread": {"type": "number", "name": "Angle Spread", "default": 20},
            "velocity": {
              "type": "range",
              "name": "Velocity Range",
              "default": {"min": 0, "max": 0.4},
            },
          },
        },
      },
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "label",
    name: "Label",
    description: "Puts some text in the overlay",
    icon: "mdi mdi-cursor-text",
    defaultSize: {"width": 300, "height": 200},
    config: {
      "message": {
        "type": "string",
        "default": "Label",
        "template": true,
        "multiLine": true,
      },
      "font": {
        "type": "object",
        "name": "Font",
        "default": {
          "fontSize": 65,
          "fontColor": "#FFFFFF",
          "fontFamily": "Impact",
          "fontWeight": 300,
          "stroke": {"width": 4, "color": "#000000"},
        },
        "fields": {
          "fontFamily": {
            "type": "string",
            "name": "Font Family",
            "default": "Impact",
          },
          "fontSize": {"type": "number", "name": "Size", "default": 65},
          "fontColor": {
            "type": "color",
            "name": "Font Color",
            "default": "#FFFFFF",
          },
          "stroke": {
            "type": "object",
            "name": "Stroke",
            "default": {"width": 4, "color": "#000000"},
            "fields": {
              "width": {"type": "number", "name": "Width", "default": 4},
              "color": {
                "type": "color",
                "name": "Stroke Color",
                "default": "#000000",
              },
            },
          },
          "shadow": {
            "type": "object",
            "name": "Shadow",
            "fields": {
              "blur": {"type": "number", "name": "Blur", "default": 4},
              "color": {
                "type": "color",
                "name": "Shadow Color",
                "default": "#FFFFFF",
              },
              "offsetX": {"type": "number", "name": "Offset X", "default": 0},
              "offsetY": {"type": "number", "name": "Offset Y", "default": 0},
            },
          },
        },
      },
      "textAlign": {
        "type": "object",
        "name": "Text Align",
        "default": {"textAlign": "left"},
        "fields": {
          "textAlign": {
            "type": "enum",
            "name": "Alignment",
            "default": "left",
            "enum": ["left", "center", "right", "justify"],
          },
        },
      },
      "block": {
        "type": "object",
        "name": "Block",
        "default": {
          "margin": {"top": 0, "bottom": 0, "left": 0, "right": 0},
          "padding": {"top": 0, "bottom": 0, "left": 0, "right": 0},
          "horizontalAlign": "left",
          "verticalAlign": "top",
        },
        "fields": {
          "margin": {
            "type": "object",
            "name": "Margin",
            "default": {"top": 0, "bottom": 0, "left": 0, "right": 0},
            "fields": {
              "top": {"type": "number", "default": 0},
              "bottom": {"type": "number", "default": 0},
              "left": {"type": "number", "default": 0},
              "right": {"type": "number", "default": 0},
            },
          },
          "padding": {
            "type": "object",
            "name": "Padding",
            "default": {"top": 0, "bottom": 0, "left": 0, "right": 0},
            "fields": {
              "top": {"type": "number", "default": 0},
              "bottom": {"type": "number", "default": 0},
              "left": {"type": "number", "default": 0},
              "right": {"type": "number", "default": 0},
            },
          },
          "horizontalAlign": {
            "type": "enum",
            "name": "Horizontal Align",
            "default": "left",
            "enum": ["left", "center", "right"],
          },
          "verticalAlign": {
            "type": "enum",
            "name": "Vertical Align",
            "default": "top",
            "enum": ["top", "center", "bottom"],
          },
        },
      },
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "leaderboard",
    name: "Leader Board (Beta)",
    description: "Displays ranked viewer data.",
    icon: "mdi mdi-table",
    defaultSize: {"width": 300, "height": 500},
    config: {
      "sortBy": {"type": "viewerVariable"},
      "sortOrder": {"type": "number", "default": -1},
      "count": {"type": "number", "default": 10, "min": 1, "max": 50},
      "variables": {
        "type": "array",
        "name": "Display Variables",
        "itemSchema": {
          "type": "object",
          "fields": {
            "variable": {"type": "viewerVariable", "name": "Variable"},
            "font": {
              "type": "object",
              "name": "Font",
              "fields": {
                "fontFamily": {
                  "type": "string",
                  "name": "Font Family",
                  "default": "Impact",
                },
                "fontSize": {"type": "number", "name": "Size", "default": 65},
                "fontColor": {
                  "type": "color",
                  "name": "Font Color",
                  "default": "#FFFFFF",
                },
                "fontWeight": {
                  "type": "number",
                  "name": "Weight",
                  "default": 300,
                },
                "stroke": {
                  "type": "object",
                  "name": "Stroke",
                  "default": {"width": 4, "color": "#000000"},
                  "fields": {
                    "width": {"type": "number", "name": "Width", "default": 4},
                    "color": {
                      "type": "color",
                      "name": "Stroke Color",
                      "default": "#000000",
                    },
                  },
                },
                "shadow": {
                  "type": "object",
                  "name": "Shadow",
                  "fields": {
                    "blur": {"type": "number", "name": "Blur", "default": 4},
                    "color": {
                      "type": "color",
                      "name": "Shadow Color",
                      "default": "#FFFFFF",
                    },
                    "offsetX": {
                      "type": "number",
                      "name": "Offset X",
                      "default": 0,
                    },
                    "offsetY": {
                      "type": "number",
                      "name": "Offset Y",
                      "default": 0,
                    },
                  },
                },
              },
            },
            "textAlign": {
              "type": "object",
              "name": "Align",
              "default": {"textAlign": "left"},
              "fields": {
                "textAlign": {
                  "type": "enum",
                  "name": "Alignment",
                  "default": "left",
                  "enum": ["left", "center", "right", "justify"],
                },
              },
            },
            "background": {
              "type": "object",
              "name": "Background",
              "default": {"elements": []},
              "fields": {
                "color": {"type": "color", "name": "Color"},
                "elements": {
                  "type": "array",
                  "name": "Layers",
                  "itemSchema": {
                    "type": "object",
                    "fields": {
                      "image": {"type": "string", "name": "Image"},
                    },
                  },
                },
              },
            },
            "block": {
              "type": "object",
              "name": "Block",
              "default": {
                "padding": {"top": 0, "bottom": 0, "left": 0, "right": 0},
                "verticalAlign": "top",
              },
              "fields": {
                "padding": {
                  "type": "object",
                  "name": "Padding",
                  "default": {"top": 0, "bottom": 0, "left": 0, "right": 0},
                  "fields": {
                    "top": {"type": "number", "default": 0},
                    "bottom": {"type": "number", "default": 0},
                    "left": {"type": "number", "default": 0},
                    "right": {"type": "number", "default": 0},
                  },
                },
                "verticalAlign": {
                  "type": "enum",
                  "name": "Vertical Align",
                  "default": "top",
                  "enum": ["top", "center", "bottom"],
                },
              },
            },
          },
        },
      },
      "nameFont": {
        "type": "object",
        "name": "Name Font",
        "default": {
          "fontSize": 65,
          "fontColor": "#FFFFFF",
          "fontFamily": "Impact",
          "fontWeight": 300,
          "stroke": {"width": 4, "color": "#000000"},
        },
        "fields": {
          "fontFamily": {
            "type": "string",
            "name": "Font Family",
            "default": "Impact",
          },
          "fontSize": {"type": "number", "name": "Size", "default": 65},
          "fontColor": {
            "type": "color",
            "name": "Font Color",
            "default": "#FFFFFF",
          },
          "fontWeight": {"type": "number", "name": "Weight", "default": 300},
          "stroke": {
            "type": "object",
            "name": "Stroke",
            "default": {"width": 4, "color": "#000000"},
            "fields": {
              "width": {"type": "number", "name": "Width", "default": 4},
              "color": {
                "type": "color",
                "name": "Stroke Color",
                "default": "#000000",
              },
            },
          },
          "shadow": {
            "type": "object",
            "name": "Shadow",
            "fields": {
              "blur": {"type": "number", "name": "Blur", "default": 4},
              "color": {
                "type": "color",
                "name": "Shadow Color",
                "default": "#FFFFFF",
              },
              "offsetX": {"type": "number", "name": "Offset X", "default": 0},
              "offsetY": {"type": "number", "name": "Offset Y", "default": 0},
            },
          },
        },
      },
      "nameTextAlign": {
        "type": "object",
        "name": "Name Align",
        "default": {"textAlign": "left"},
        "fields": {
          "textAlign": {
            "type": "enum",
            "name": "Alignment",
            "default": "left",
            "enum": ["left", "center", "right", "justify"],
          },
        },
      },
      "nameBackground": {
        "type": "object",
        "name": "Name Background",
        "default": {"elements": []},
        "fields": {
          "color": {"type": "color", "name": "Color"},
          "elements": {
            "type": "array",
            "name": "Layers",
            "itemSchema": {
              "type": "object",
              "fields": {
                "image": {"type": "string", "name": "Image"},
              },
            },
          },
        },
      },
      "nameBlock": {
        "type": "object",
        "name": "Name Block",
        "default": {
          "padding": {"top": 0, "bottom": 0, "left": 0, "right": 0},
          "verticalAlign": "top",
        },
        "fields": {
          "padding": {
            "type": "object",
            "name": "Padding",
            "default": {"top": 0, "bottom": 0, "left": 0, "right": 0},
            "fields": {
              "top": {"type": "number", "default": 0},
              "bottom": {"type": "number", "default": 0},
              "left": {"type": "number", "default": 0},
              "right": {"type": "number", "default": 0},
            },
          },
          "verticalAlign": {
            "type": "enum",
            "name": "Vertical Align",
            "default": "top",
            "enum": ["top", "center", "bottom"],
          },
        },
      },
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "paidAlert",
    name: "Paid Alert",
    description:
        "Displays YouTube paid messages, donations, and support events.",
    icon: "mdi mdi-cash-star",
    capabilities: {
      "events": ["showrunner_paid_alert"],
    },
    defaultSize: {"width": 680, "height": 190},
    config: {
      "fontFamily": {"type": "string", "default": "Inter, Arial, sans-serif"},
      "accentColor": {"type": "string", "default": "#ffd166"},
      "backgroundColor": {"type": "string", "default": "#131313"},
      "backgroundOpacity": {"type": "number", "default": 0.86},
      "duration": {"type": "number", "default": 7},
      "previewTitle": {"type": "string", "default": "Super Chat"},
      "previewViewer": {"type": "string", "default": "Supporter"},
      "previewMessage": {"type": "string", "default": "Thanks for the stream!"},
      "previewAmount": {"type": "string", "default": "10.00"},
      "previewCurrency": {"type": "string", "default": "USD"},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "sceneBanner",
    name: "Scene Banner",
    description: "Displays scene begin/end automation events.",
    icon: "mdi mdi-motion-play-outline",
    capabilities: {
      "events": ["showrunner_scene_event"],
    },
    defaultSize: {"width": 900, "height": 170},
    config: {
      "fontFamily": {"type": "string", "default": "Inter, Arial, sans-serif"},
      "accentColor": {"type": "string", "default": "#9146ff"},
      "backgroundColor": {"type": "string", "default": "#101010"},
      "backgroundOpacity": {"type": "number", "default": 0.82},
      "duration": {"type": "number", "default": 6},
      "previewTitle": {"type": "string", "default": "Starting Soon"},
      "previewSubtitle": {
        "type": "string",
        "default": "Scene automation preview",
      },
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "overlays",
    id: "shaderLayer",
    name: "Shader Layer",
    description: "Renders a bundled or locally edited WebGL shader.",
    icon: "mdi mdi-magic-staff",
    capabilities: {"resizable": true},
    defaultSize: {"width": 900, "height": 500},
    config: {
      "preset": {
        "type": "string",
        "name": "Shader Preset",
        "default": "aurora",
        "enum": [
          "aurora",
          "grid",
          "plasma",
          "nebula",
          "scanlines",
          "vortex",
          "custom",
        ],
      },
      "customFragmentShader": {"type": "string", "multiLine": true},
      "accentColor": {"type": "string", "default": "#9146ff"},
      "secondaryColor": {"type": "string", "default": "#00d1ff"},
      "intensity": {"type": "number", "default": 0.8},
      "speed": {"type": "number", "default": 1},
      "opacity": {"type": "number", "default": 1},
      "blendMode": {"type": "string", "default": "normal"},
      "text": {"type": "string", "default": "", "template": true},
      "shaderGraph": {"type": "object", "name": "Shader Graph (JSON)"},
      "shaderUniforms": {"type": "object"},
      "shaderUniformBindings": {"type": "object"},
    },
  ),
  GeneratedOverlayWidget(
    pluginId: "random",
    id: "wheel",
    name: "Wheel",
    description: "A wheel for randomly selecting things",
    icon: "mdi mdi-tire",
    capabilities: {
      "commands": ["spinWheel"],
      "resizable": true,
    },
    defaultSize: {"width": 500, "height": 500},
    config: {
      "slices": {"type": "number", "default": 12},
      "items": {"type": "array"},
      "style": {"type": "array"},
      "damping": {"type": "object"},
      "clicker": {"type": "object"},
    },
  ),
];
