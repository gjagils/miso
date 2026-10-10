import Foundation
import Testing
@testable import AHRecepten

/// Port van `scale_line`, `recipe_servings` en `cook_hints` (backend/app/planning.py, tests/test_plan.py).
struct CookLogicTests {
    @Test func scaleLineLikeServer() {
        #expect(IngredientScaler.scaleLine("200 g kipfilet", factor: 2) == "400 g kipfilet")
        #expect(IngredientScaler.scaleLine("½ ui", factor: 2) == "1 ui")
        #expect(IngredientScaler.scaleLine("1/2 tl zout", factor: 3) == "1½ tl zout")
        #expect(IngredientScaler.scaleLine("2-3 tenen knoflook", factor: 2) == "4-6 tenen knoflook")
        #expect(IngredientScaler.scaleLine("zout en peper", factor: 2) == "zout en peper")
        #expect(IngredientScaler.scaleLine("300 g rijst", factor: 1) == "300 g rijst")
    }

    @Test func scaleLineEdgeCases() {
        #expect(IngredientScaler.scaleLine("1,5 dl room", factor: 2) == "3 dl room")
        #expect(IngredientScaler.scaleLine("1 ui", factor: 1.5) == "1½ ui")
        #expect(IngredientScaler.scaleLine("1 ui", factor: 0.25) == "¼ ui")
        #expect(IngredientScaler.scaleLine("3 eieren", factor: 0.75) == "2¼ eieren")
        #expect(IngredientScaler.scaleLine("3 g kaas", factor: 1.4) == "4,2 g kaas")
        #expect(IngredientScaler.scaleLine("2 - 3 el olie", factor: 2) == "4-6 el olie")
        #expect(IngredientScaler.scaleLine("  2 uien", factor: 2) == "4 uien")
    }

    @Test func servingsAndFactor() {
        #expect(IngredientScaler.servings("4 personen") == 4)
        #expect(IngredientScaler.servings("4-6 pers.") == 4)
        #expect(IngredientScaler.servings("") == 4)
        #expect(IngredientScaler.servings("100 personen") == 4)
        #expect(IngredientScaler.servings("2") == 2)
        #expect(IngredientScaler.factor(persons: 6, servings: "4 personen") == 1.5)
        #expect(IngredientScaler.factor(persons: nil, servings: "2") == 1)
        #expect(IngredientScaler.factor(persons: 4, servings: "") == 1)
        #expect(!IngredientScaler.needsScaling(1))
    }

    @Test func ovenTimeMakesItHonest() {
        let h = CookHints(instructions: ["Snijd de groenten.",
                                         "Bak de lasagne in ca. 30 min. in de oven op 200 °C goudbruin."],
                          totalTime: "25 minuten")
        #expect(h.ovenMinutes == 30)
        #expect(h.ovenTemperature == "200")
        #expect(h.minutes == 55)
        #expect(h.longer)
        #expect(h.timeText == "± 55 min (oven 30 min)")
        #expect(h.ovenText == "Zet eerst de oven op 200 °C")
    }

    @Test func noOven() {
        let h = CookHints(instructions: ["Kook de pasta 10 min.", "Roer de saus erdoor."], totalTime: "20 min")
        #expect(h.ovenMinutes == nil)
        #expect(h.ovenTemperature == nil)
        #expect(h.minutes == 20)
        #expect(!h.longer)
        #expect(h.timeText == "± 20 min")
    }

    @Test func listedTimeAlreadyIncludesOven() {
        let h = CookHints(instructions: ["Verwarm de oven voor op 180 graden. Bak 20-25 min in de oven."],
                          totalTime: "60 min")
        #expect(h.ovenMinutes == 20)
        #expect(h.ovenTemperature == "180")
        #expect(h.minutes == 60)
        #expect(!h.longer)
    }

    @Test func unknownTime() {
        let h = CookHints(instructions: [], totalTime: "")
        #expect(h.minutes == nil)
        #expect(h.timeText == nil)
    }

    @Test func shortMealKitNames() {
        #expect(RecipeDisplayName.short("AH gesneden verspakket 'Indonesische' nasi goreng") == "Indonesische nasi goreng")
        #expect(RecipeDisplayName.short("AH verspakket shakshuka") == "Shakshuka")
        #expect(RecipeDisplayName.short("AH excellent verspakket \"Japanse\" teriyaki") == "Japanse teriyaki")
        #expect(RecipeDisplayName.short("ah biologisch gesneden verspakket gado gado") == "Gado gado")
        #expect(RecipeDisplayName.short("Oma's appeltaart") == "Oma's appeltaart")
        #expect(RecipeDisplayName.isPack("AH verspakket shakshuka"))
        #expect(!RecipeDisplayName.isPack("Lasagne"))
    }
}
