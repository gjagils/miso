// Safari-preprocessing voor "Deel naar Miso": leest de pagina die de gebruiker open heeft.
// Dezelfde functie wordt in de extensie ook in een WKWebView uitgevoerd (zie PageCollector.swift).
var MisoCollectPage = function() {
    var ld = [];
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < scripts.length; i++) {
        var t = (scripts[i].textContent || "").trim();
        if (t) { ld.push(t); }
    }
    var text = document.body ? (document.body.innerText || "") : "";
    if (text.length > 60000) { text = text.substring(0, 60000); }
    return { title: document.title || "", url: location.href, jsonld: ld, text: text };
};

var ExtensionPreprocessingJS = {
    run: function(args) { args.completionFunction(MisoCollectPage()); },
    finalize: function(args) {}
};
