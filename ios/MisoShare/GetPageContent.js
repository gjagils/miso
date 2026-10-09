// Safari-preprocessing voor "Deel naar Miso": leest de pagina die de gebruiker open heeft.
// Dezelfde functie wordt in de extensie ook in een WKWebView uitgevoerd (zie PageCollector.swift).
var MisoCollectPage = function() {
    function absolute(u) {
        if (!u || typeof u !== "string") { return ""; }
        try { return new URL(u.trim(), location.href).href; } catch (e) { return ""; }
    }

    // JSON-LD "image": string, lijst, of object met url/contentUrl.
    function ldImage(img) {
        if (!img) { return ""; }
        if (typeof img === "string") { return absolute(img); }
        if (Array.isArray(img)) {
            for (var i = 0; i < img.length; i++) {
                var u = ldImage(img[i]);
                if (u) { return u; }
            }
            return "";
        }
        if (typeof img === "object") { return absolute(img.url || img.contentUrl || ""); }
        return "";
    }

    function isRecipe(node) {
        var t = node && node["@type"];
        if (!t) { return false; }
        if (Array.isArray(t)) { return t.indexOf("Recipe") >= 0; }
        return t === "Recipe";
    }

    // Zoek een Recipe-knoop (ook in @graph en lijsten) en geef de foto terug.
    function recipeImage(node, depth) {
        if (!node || typeof node !== "object" || depth > 6) { return ""; }
        if (Array.isArray(node)) {
            for (var i = 0; i < node.length; i++) {
                var u = recipeImage(node[i], depth + 1);
                if (u) { return u; }
            }
            return "";
        }
        if (isRecipe(node)) {
            var img = ldImage(node.image) || ldImage(node.thumbnailUrl);
            if (img) { return img; }
        }
        if (node["@graph"]) { return recipeImage(node["@graph"], depth + 1); }
        if (node.mainEntity) { return recipeImage(node.mainEntity, depth + 1); }
        return "";
    }

    function metaImage() {
        var selectors = ['meta[property="og:image"]', 'meta[property="og:image:url"]', 'meta[name="og:image"]',
                         'meta[name="twitter:image"]', 'meta[property="twitter:image"]', 'meta[name="twitter:image:src"]'];
        for (var i = 0; i < selectors.length; i++) {
            var m = document.querySelector(selectors[i]);
            var u = m ? absolute(m.getAttribute("content")) : "";
            if (u) { return u; }
        }
        return "";
    }

    // Grootste foto in het artikel (of de hoofdinhoud), als er niets beters is.
    function largestImage() {
        var root = document.querySelector("article") || document.querySelector("main") || document.body;
        if (!root) { return ""; }
        var imgs = root.querySelectorAll("img");
        var best = "", bestArea = 0;
        for (var i = 0; i < imgs.length; i++) {
            var img = imgs[i];
            var w = img.naturalWidth || img.width || 0, h = img.naturalHeight || img.height || 0;
            var src = absolute(img.currentSrc || img.src || img.getAttribute("data-src") || "");
            if (!src || src.indexOf("data:") === 0) { continue; }
            if (w * h > bestArea) { bestArea = w * h; best = src; }
        }
        return bestArea >= 200 * 150 ? best : "";
    }

    var ld = [];
    var image = "";
    var scripts = document.querySelectorAll('script[type="application/ld+json"]');
    for (var i = 0; i < scripts.length; i++) {
        var t = (scripts[i].textContent || "").trim();
        if (!t) { continue; }
        ld.push(t);
        if (!image) {
            try { image = recipeImage(JSON.parse(t), 0); } catch (e) {}
        }
    }
    if (!image) { image = metaImage(); }
    if (!image) { image = largestImage(); }

    var text = document.body ? (document.body.innerText || "") : "";
    if (text.length > 60000) { text = text.substring(0, 60000); }
    return { title: document.title || "", url: location.href, jsonld: ld, text: text, image: image };
};

var ExtensionPreprocessingJS = {
    run: function(args) { args.completionFunction(MisoCollectPage()); },
    finalize: function(args) {}
};
