import SwiftUI
import WebKit

/// Shows Giotto's SVG with pan, zoom and component selection. Giotto renders the diagram (in the
/// helper); this view only frames it. The page loads no network resources.
struct DiagramWebView: NSViewRepresentable {
    let svg: String
    let onSelect: (String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onSelect: onSelect) }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "select")
        config.websiteDataStore = .nonPersistent()
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.navigationDelegate = context.coordinator
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.onSelect = onSelect
        guard context.coordinator.loaded != svg else { return }
        context.coordinator.loaded = svg
        view.loadHTMLString(Self.page(svg), baseURL: nil)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "select")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onSelect: (String?) -> Void
        var loaded: String?
        init(onSelect: @escaping (String?) -> Void) { self.onSelect = onSelect }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            onSelect(message.body as? String)
        }

        // Only the inline document; links inside the diagram never navigate the view.
        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            decisionHandler(action.navigationType == .other ? .allow : .cancel)
        }
    }

    static func page(_ svg: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:; font-src data:">
        <style>
          html,body{margin:0;height:100%;overflow:hidden;background:transparent;font-family:-apple-system,sans-serif}
          #stage{width:100%;height:100%;cursor:grab}
          #stage.dragging{cursor:grabbing}
          #canvas{transform-origin:0 0;position:absolute;left:0;top:0}
          g[data-id]{cursor:pointer}
          g[data-id]:hover{filter:brightness(1.25)}
          g[data-id].selected{filter:drop-shadow(0 0 6px #a78bfa) brightness(1.3)}
          #hint{position:fixed;right:12px;bottom:10px;color:#8b85a0;font-size:11px}
        </style></head><body>
        <div id="stage"><div id="canvas">\(svg)</div></div>
        <div id="hint">scroll or pinch to zoom · drag to pan · double-click to fit</div>
        <script>
        const stage=document.getElementById('stage'),canvas=document.getElementById('canvas'),svg=canvas.querySelector('svg');
        let s=1,x=0,y=0,drag=null,moved=false;
        const apply=()=>canvas.style.transform=`translate(${x}px,${y}px) scale(${s})`;
        function fit(){const w=svg.width.baseVal.value||svg.getBBox().width,h=svg.height.baseVal.value||svg.getBBox().height;
          s=Math.min(innerWidth/w,(innerHeight-60)/h,1.6)*0.94;x=(innerWidth-w*s)/2;y=Math.max(56,(innerHeight-h*s)/2);apply();}
        fit();addEventListener('resize',fit);
        stage.addEventListener('wheel',e=>{e.preventDefault();
          if(e.ctrlKey||e.metaKey){const k=Math.exp(-e.deltaY*0.01),n=Math.min(6,Math.max(0.1,s*k));x=e.clientX-(e.clientX-x)*n/s;y=e.clientY-(e.clientY-y)*n/s;s=n;}
          else{x-=e.deltaX;y-=e.deltaY;} apply();},{passive:false});
        stage.addEventListener('mousedown',e=>{drag={x:e.clientX-x,y:e.clientY-y};moved=false;stage.classList.add('dragging')});
        addEventListener('mousemove',e=>{if(!drag)return;moved=true;x=e.clientX-drag.x;y=e.clientY-drag.y;apply()});
        addEventListener('mouseup',()=>{drag=null;stage.classList.remove('dragging')});
        stage.addEventListener('dblclick',fit);
        stage.addEventListener('click',e=>{if(moved)return;const g=e.target.closest('g[data-id]');
          document.querySelectorAll('g.selected').forEach(n=>n.classList.remove('selected'));
          if(g){g.classList.add('selected')}window.webkit.messageHandlers.select.postMessage(g?g.dataset.id:null)});
        </script></body></html>
        """
    }
}
