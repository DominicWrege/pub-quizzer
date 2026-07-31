alias PubQuizzer.Repo
alias PubQuizzer.Accounts
alias PubQuizzer.Quiz.{Topic, Question}

# E2E test user for Playwright (see e2e/ and playwright.config.ts).
# Only created when seeding the E2E database — the dev DB never gets it.
# Idempotent: only inserts if this email doesn't already exist.
if System.get_env("E2E") == "1" do
  case Accounts.get_user_by_email("e2e@localhost.test") do
    nil ->
      Accounts.create_user!(%{
        email: "e2e@localhost.test",
        name: "E2E Host",
        role: "superadmin",
        active: true
      })

      IO.puts("Created E2E test user (e2e@localhost.test).")

    _user ->
      :ok
  end

  # Moderator-role user: the onboarding guide only shows for moderators,
  # so the guide E2E test needs a non-superadmin account.
  case Accounts.get_user_by_email("mod-e2e@localhost.test") do
    nil ->
      Accounts.create_user!(%{
        email: "mod-e2e@localhost.test",
        name: "E2E Moderator",
        role: "moderator",
        active: true
      })

      IO.puts("Created E2E moderator user (mod-e2e@localhost.test).")

    _user ->
      :ok
  end
end

if Repo.aggregate(Topic, :count) == 0 do
  topics_data = [
    %{
      name: "Erdkunde",
      description: "Hauptstädte, Flüsse, Berge und mehr.",
      questions: [
        {"Welches Land hat die meisten Nachbarländer weltweit?",
         [
           "Deutschland grenzt an insgesamt 9 direkte Nachbarn in Mitteleuropa, darunter Frankreich, Polen und die Niederlande.",
           "Russland teilt seine Grenzen mit insgesamt 14 direkten Nachbarn quer über Eurasien, von Norwegen bis Nordkorea.",
           "China hat insgesamt 14 direkte Nachbarn in Ostasien, darunter Indien, Russland und Vietnam.",
           "Brasilien grenzt an insgesamt 10 direkte Nachbarn in Südamerika, mehr als jedes andere Land des Kontinents."
         ], 1},
        {"Der Amazonas-Regenwald erstreckt sich hauptsächlich über welches Land?",
         [
           "Peru, in dessen Andenregion die Quellflüsse des Amazonas entspringen und den Regenwald speisen.",
           "Kolumbien, das große Teile des Regenwaldes im Nordwesten des Amazonasbeckens beherbergt.",
           "Brasilien, auf dessen Staatsgebiet sich rund 60 % der gesamten Regenwaldfläche des Amazonas befinden.",
           "Bolivien, das im südwestlichen Bereich des Amazonasbeckens liegt und einen kleineren Anteil am Regenwald hat."
         ], 2},
        {"Welche Meerenge trennt Europa von Afrika?",
         [
           "Die Straße von Gibraltar, die zwischen Spanien und Marokko liegt und das Mittelmeer mit dem Atlantik verbindet.",
           "Der Bosporus, der das Schwarze Meer mit dem Marmarameer verbindet und den europäischen vom asiatischen Teil der Türkei trennt.",
           "Die Straße von Sizilien, die zwischen Italien und Tunesien verläuft und das westliche vom östlichen Mittelmeer trennt.",
           "Der Ärmelkanal, der zwischen Großbritannien und Frankreich liegt und die Nordsee mit dem Atlantik verbindet."
         ], 0},
        {"Welches ist das flächenmäßig größte Binnenland der Welt?",
         [
           "Die Mongolei, ein ausgedehntes Hochland in Zentralasien, das aber kleiner ist als Kasachstan.",
           "Kasachstan, das größte Binnenland der Erde und zugleich das neuntgrößte Land der Welt nach Fläche.",
           "Der Tschad, ein großes Land in der Sahelzone Afrikas, das allerdings deutlich kleiner ist als Kasachstan.",
           "Usbekistan, ein zentralasiatischer Binnenstaat, der flächenmäßig hinter Kasachstan und der Mongolei zurückliegt."
         ], 1},
        {"Der Mount Everest liegt an der Grenze zwischen welchen zwei Ländern?",
         [
           "Indien und China, die sich den Himalaya teilen, wobei der Everest jedoch nicht an der indischen Grenze liegt.",
           "Nepal und Bhutan, zwei kleine Himalaya-Königreiche, zwischen denen der Everest allerdings nicht verläuft.",
           "Nepal und China, genauer gesagt die Autonome Region Tibet, zwischen denen der höchste Berg der Erde liegt.",
           "Indien und Nepal, an deren Grenze sich die südlichen Ausläufer des Himalaya-Gebirges befinden."
         ], 2}
      ]
    },
    %{
      name: "Wissenschaft & Natur",
      description: "Biologie, Chemie, Physik und die Natur.",
      questions: [
        {"Welches Element ist das häufigste im Universum?",
         [
           "Sauerstoff ist das auf der Erde am häufigsten vorkommende Element, macht aber nur einen winzigen Bruchteil der Materie im Universum aus.",
           "Helium ist das zweithäufigste Element im Universum und entsteht vor allem durch Kernfusion in Sternen.",
           "Kohlenstoff bildet die Grundlage allen bekannten Lebens im Universum, ist aber kosmisch gesehen relativ selten.",
           "Wasserstoff macht etwa 75 % der gesamten sichtbaren baryonischen Masse des Universums aus und ist damit das häufigste Element."
         ], 3},
        {"Wie nennt man den Prozess, bei dem Pflanzen Licht in Energie umwandeln?",
         [
           "Zellatmung ist der Prozess, bei dem Zellen Energie aus Glucose gewinnen und dabei Kohlenstoffdioxid freisetzen.",
           "Photosynthese ist der biochemische Vorgang, bei dem Pflanzen mithilfe von Chlorophyll Lichtenergie in chemische Energie umwandeln.",
           "Gärung ist ein anaerober Stoffwechselprozess, bei dem organische Stoffe ohne Sauerstoff zur Energiegewinnung abgebaut werden.",
           "Transpiration bezeichnet die Abgabe von Wasserdampf über die Spaltöffnungen der Blätter, dient aber nicht der Energiegewinnung."
         ], 1},
        {"Welcher Planet unseres Sonnensystems hat die meisten Monde?",
         [
           "Jupiter ist der größte Planet und besitzt mindestens 95 bekannte Monde, darunter die vier großen Galileischen Monde.",
           "Saturn ist der Ringplanet mit mindestens 146 bestätigten Monden und hält damit den Rekord in unserem Sonnensystem.",
           "Uranus ist ein Eisriese mit mindestens 27 bekannten Monden, die nach Figuren aus Shakespeares Werken benannt sind.",
           "Neptun ist der äußerste Planet mit mindestens 16 bekannten Monden, von denen Triton der mit Abstand größte ist."
         ], 1},
        {"Was bezeichnet der Begriff DNA in der Biologie vollständig?",
         [
           "Desoxyribonukleinsäure ist der Träger der genetischen Information in allen bekannten Lebewesen und vielen Viren.",
           "Dinatriumadenosintriphosphat ist ein wichtiger Energielieferant in Zellen, wird aber als ATP abgekürzt und nicht als DNA.",
           "Deoxyribonucleinacid ist die englische Bezeichnung für die DNA, die Abkürzung steht jedoch für den deutschen Begriff Desoxyribonukleinsäure.",
           "Dinitroamin ist eine veraltete chemische Bezeichnung und hat nichts mit der Erbinformation von Lebewesen zu tun."
         ], 0},
        {"Welches Tier hat das größte Gehirn im Verhältnis zur Körpergröße?",
         [
           "Der Elefant besitzt ein Gehirn von etwa 5 Kilogramm, das absolut gesehen riesig ist, aber im Verhältnis zum Körpergewicht eher klein.",
           "Der Blauwal ist das größte Tier, das jemals auf der Erde gelebt hat, sein Gehirn wiegt etwa 7 Kilogramm, ist aber relativ zum Körper winzig.",
           "Die Ameise hat ein für Insekten außergewöhnlich großes Gehirn, das aber im Verhältnis zur Körpergröße nicht mit dem des Menschen vergleichbar ist.",
           "Der Mensch besitzt im Verhältnis zur Körpergröße eines der größten Gehirne, wobei das Verhältnis bei manchen Vogelarten und Spitzmäusen sogar noch höher liegt."
         ], 3}
      ]
    },
    %{
      name: "Filme & Serien",
      description: "Von Hollywood-Blockbustern bis zu Kultserien.",
      questions: [
        {"Welcher Schauspieler spielte die Hauptrolle in Forrest Gump?",
         [
           "Robert De Niro ist bekannt für intensive Charakterstudien in Filmen wie Taxi Driver und Raging Bull, spielte aber nicht Forrest Gump.",
           "Tom Hanks spielte die Titelrolle in Forrest Gump und gewann für diese Darstellung den Oscar als bester Hauptdarsteller.",
           "Kevin Costner feierte in den 1990er Jahren viele Erfolge mit Filmen wie Der mit dem Wolf tanzt, spielte jedoch nicht Forrest Gump.",
           "Robin Williams war für seine Vielseitigkeit bekannt und spielte in Filmen wie Good Will Hunting, aber nicht in Forrest Gump."
         ], 1},
        {"In welchem Jahr wurde die erste Folge von Game of Thrones ausgestrahlt?",
         [
           "Die erste Staffel von Game of Thrones wurde 2009 produziert, aber die Ausstrahlung begann erst etwas später auf HBO.",
           "Die Serie startete 2010, zeitgleich mit dem Ende von Lost, und wurde schnell zu einem weltweiten Phänomen.",
           "Game of Thrones wurde erstmals 2011 auf HBO ausgestrahlt und basiert auf der Romanreihe Das Lied von Eis und Feuer von George R. R. Martin.",
           "Die Serie begann 2012 nach jahrelanger Entwicklung durch die Showrunner David Benioff und D. B. Weiss."
         ], 2},
        {"Welcher Regisseur drehte den Thriller-Klassiker Der weiße Hai?",
         [
           "Francis Ford Coppola ist der Regisseur der Paten-Trilogie und von Apocalypse Now, führte aber nicht bei Der weiße Hai Regie.",
           "Steven Spielberg drehte 1975 den Film Der weiße Hai und feierte damit seinen großen Durchbruch als Hollywood-Regisseur.",
           "George Lucas ist der Schöpfer des Star-Wars-Universums und war mit Spielberg befreundet, drehte aber nicht Der weiße Hai.",
           "James Cameron inszenierte später Filme wie Titanic und Avatar, war aber 1975 noch nicht als Regisseur tätig."
         ], 1},
        {"Welche Serie hält den Rekord für die meisten Emmy-Auszeichnungen?",
         [
           "Game of Thrones gewann insgesamt 59 Emmys und ist damit eine der erfolgreichsten Serien, hält aber nicht den Rekord.",
           "Breaking Bad ist eine gefeierte AMC-Serie über einen Chemielehrer, die zahlreiche Emmys gewann, aber nicht die meisten.",
           "The Sopranos gilt als eine der Pionierserien des modernen Fernsehens und gewann viele Emmys, aber nicht den Rekord.",
           "Saturday Night Live ist die langlebige NBC-Comedyshow, die mit über 90 Emmys die meisten Auszeichnungen aller Serien erhalten hat."
         ], 3},
        {"Aus welchem Land stammt der Film Parasite, der 2020 den Oscar gewann?",
         [
           "Japan ist bekannt für seine vielfältige und traditionsreiche Filmindustrie, aber Parasite ist kein japanischer Film.",
           "Südkorea, mit dem Regisseur Bong Joon-ho, gewann 2020 mit Parasite als erster nicht-englischsprachiger Film den Oscar für den besten Film.",
           "China hat in den letzten Jahren international große Erfolge gefeiert, aber Parasite stammt nicht aus China.",
           "Thailand verfügt über eine wachsende, international beachtete Filmszene, produzierte aber nicht Parasite."
         ], 1}
      ]
    },
    %{
      name: "Musik",
      description: "Von Klassik bis Pop und alles dazwischen.",
      questions: [
        {"Welche Band veröffentlichte das meistverkaufte Album aller Zeiten?",
         [
           "Michael Jackson veröffentlichte 1982 das bahnbrechende Album Thriller, das mit über 100 Millionen verkauften Exemplaren das meistverkaufte Album aller Zeiten ist.",
           "The Beatles veröffentlichten 1967 das einflussreiche Album Sgt. Pepper's Lonely Hearts Club Band, das aber nicht das meistverkaufte Album ist.",
           "Pink Floyd schufen 1973 das legendäre Konzeptalbum The Dark Side of the Moon, das sich sehr gut verkaufte, aber nicht den Rekord hält.",
           "Die Eagles veröffentlichten 1976 ihr Greatest Hits-Album mit Hotel California, das zu den meistverkauften Alben zählt, aber nicht auf Platz eins steht."
         ], 0},
        {"Aus wie vielen Musikern besteht ein klassisches Streichquartett?",
         [
           "Ein klassisches Streichquartett besteht aus drei Musikern, was jedoch ein Streichtrio wäre und nicht dem Standard entspricht.",
           "Ein klassisches Streichquartett besteht aus vier Musikern mit der Besetzung von zwei Violinen, einer Viola und einem Violoncello.",
           "Ein klassisches Streichquartett besteht aus fünf Musikern, was aber ein Streichquintett wäre und eine andere Besetzung darstellt.",
           "Ein klassisches Streichquartett besteht aus sechs Musikern, was jedoch eine zu große Besetzung für die traditionelle Kammermusik wäre."
         ], 1},
        {"Welches Instrument wird auch Königin der Instrumente genannt?",
         [
           "Die Violine wird wegen ihrer Vielseitigkeit und ihres edlen Klangs geschätzt, trägt aber nicht den Beinamen Königin der Instrumente.",
           "Die Orgel wird aufgrund ihrer gewaltigen Klangfülle und imposanten Größe traditionell als die Königin der Instrumente bezeichnet.",
           "Das Klavier ist in fast jeder Musikrichtung zuhause und sehr beliebt, wird aber nicht als Königin der Instrumente bezeichnet.",
           "Die Harfe gehört zu den ältesten und elegantesten Instrumenten, trägt jedoch nicht den Titel Königin der Instrumente."
         ], 1},
        {"In welchem Jahrzehnt wurde der Rock 'n' Roll populär?",
         [
           "In den 1940er Jahren legten Künstler wie Bill Haley mit frühen Rockabilly-Aufnahmen den Grundstein, aber der große Durchbruch kam erst später.",
           "In den 1950er Jahren wurde der Rock 'n' Roll mit Legenden wie Elvis Presley, Chuck Berry und Little Richard zu einem weltweiten Phänomen.",
           "In den 1960er Jahren erlebte die Musik während der British Invasion um die Beatles und die Rolling Stones einen weiteren großen Schub.",
           "In den 1970er Jahren entwickelte sich der Rock mit dem Aufkommen von Hard Rock, Progressive Rock und Punk in viele neue Richtungen."
         ], 1},
        {"Wer komponierte die berühmte Ode an die Freude?",
         [
           "Johann Sebastian Bach war ein großer Barockkomponist, der zahlreiche Kantaten und Orgelwerke schuf, aber nicht die Ode an die Freude.",
           "Ludwig van Beethoven komponierte die Ode an die Freude als Finalsatz seiner 9. Sinfonie, die 1824 uraufgeführt wurde und heute die Europahymne ist.",
           "Wolfgang Amadeus Mozart war der Wiener Klassiker schlechthin und komponierte über 600 Werke, darunter jedoch nicht die Ode an die Freude.",
           "Johannes Brahms war ein bedeutender Komponist der Romantik, der vier Sinfonien schrieb, aber nicht die 9. Sinfonie mit der Ode an die Freude."
         ], 1}
      ]
    },
    %{
      name: "Geschichte",
      description: "Von antiken Zivilisationen bis zu modernen Ereignissen.",
      questions: [
        {"In welchem Jahr wurde die Berliner Mauer gebaut?",
         [
           "Die Berliner Mauer wurde 1959 gebaut, was jedoch nicht korrekt ist, da die massive Fluchtbewegung aus der DDR zu diesem Zeitpunkt noch nicht ihren Höhepunkt erreicht hatte.",
           "Die Berliner Mauer wurde 1961 errichtet, um die Massenflucht von DDR-Bürgern in den Westen zu stoppen, und teilte die Stadt 28 Jahre lang.",
           "Die Berliner Mauer wurde 1963 gebaut, nach der Kuba-Krise und während der Verschärfung des Kalten Krieges zwischen Ost und West.",
           "Die Berliner Mauer wurde 1965 errichtet und wurde zum bekanntesten Symbol der Teilung Europas während des Kalten Krieges."
         ], 1},
        {"Welche antike Zivilisation baute die Pyramiden von Gizeh?",
         [
           "Die Römer errichteten selbst monumentale Bauwerke wie das Kolosseum und das Pantheon, aber nicht die Pyramiden von Gizeh in Ägypten.",
           "Die alten Ägypter bauten die Pyramiden von Gizeh während der Zeit des Alten Reiches um 2500 v. Chr. als Grabstätten für ihre Pharaonen.",
           "Die Sumerer waren die erste Hochkultur in Mesopotamien und bauten Zikkurate, aber nicht die Pyramiden von Gizeh in Ägypten.",
           "Die Perser beherrschten ein riesiges Reich in Vorderasien und errichteten Paläste wie in Persepolis, aber nicht die Pyramiden von Gizeh."
         ], 1},
        {"In welchem Jahr endete der Erste Weltkrieg?",
         [
           "Der Erste Weltkrieg endete 1916, nach der äußerst verlustreichen Schlacht an der Somme und der Schlacht um Verdun an der Westfront.",
           "Der Erste Weltkrieg endete 1917, nach der Oktoberrevolution in Russland und dem darauf folgenden Waffenstillstand an der Ostfront.",
           "Der Erste Weltkrieg endete 1918 mit der Unterzeichnung des Waffenstillstands von Compiègne am 11. November, der die Kampfhandlungen beendete.",
           "Der Erste Weltkrieg endete 1919 mit dem Abschluss des Versailler Vertrags, der die formellen Friedensbedingungen für Deutschland festlegte."
         ], 2},
        {"Wer war die erste Frau im Weltraum?",
         [
           "Sally Ride war die erste US-amerikanische Frau im All und flog 1983 mit der Raumfähre Challenger, war aber nicht die erste Frau überhaupt.",
           "Valentina Tereschkowa war die erste Frau im Weltraum und flog 1963 an Bord der sowjetischen Raumkapsel Wostok 6 in die Erdumlaufbahn.",
           "Swetlana Sawizkaja war die zweite sowjetische Kosmonautin und die erste Frau, die einen Weltraumspaziergang durchführte, aber nicht die erste Frau im All.",
           "Mae Jemison war die erste afroamerikanische Frau im Weltraum und flog 1992 mit dem Space Shuttle, war aber nicht die erste Frau im All."
         ], 1},
        {"Welches Ereignis gilt als Auslöser des Zweiten Weltkriegs in Europa?",
         [
           "Der Angriff auf Pearl Harbor durch japanische Streitkräfte am 7. Dezember 1941 löste den Kriegseintritt der USA aus, aber nicht den Krieg in Europa.",
           "Der deutsche Überfall auf Polen am 1. September 1939 gilt als der unmittelbare Auslöser des Zweiten Weltkriegs in Europa, woraufhin Frankreich und Großbritannien Deutschland den Krieg erklärten.",
           "Die Unterzeichnung des Hitler-Stalin-Pakts im August 1939 war ein wichtiger diplomatischer Schritt, aber nicht der eigentliche Auslöser des Krieges.",
           "Der Anschluss Österreichs an das Deutsche Reich im März 1938 war eine bedeutende Expansion, löste aber noch nicht den Zweiten Weltkrieg aus."
         ], 1}
      ]
    },
    %{
      name: "Lange Texte",
      description: "Fragen mit besonders langen Texten zum Testen des Layouts.",
      questions: [
        {"Welche der folgenden Aussagen beschreibt den Prozess der Photosynthese am genauesten und vollständigsten, einschließlich aller beteiligten Komponenten und der resultierenden Produkte dieser fundamentalen biochemischen Reaktion?",
         [
           "Die Photosynthese wandelt Kohlenstoffdioxid und Wasser mithilfe von Lichtenergie, die durch das Chlorophyll in den Blättern absorbiert wird, in Glucose und Sauerstoff um und findet ausschließlich in den Chloroplasten der Pflanzenzellen statt.",
           "Bei der Photosynthese nehmen Pflanzen ausschließlich nachts Kohlendioxid auf und wandeln es tagsüber unter Einwirkung von Sonnenlicht in energiereiche organische Verbindungen um, was jedoch nicht dem tatsächlichen Ablauf entspricht.",
           "Die Photosynthese bezeichnet die Synthese von Proteinen und Aminosäuren aus anorganischen Stickstoffverbindungen, katalysiert durch das Enzym Nitrogenase, was jedoch vielmehr die Stickstofffixierung in den Wurzelknöllchen von Leguminosen beschreibt.",
           "Die Photosynthese beschreibt die oxidative Spaltung von Glucosemolekülen in den Mitochondrien, wobei ATP als universeller Energieträger für sämtliche zellulären Stoffwechselprozesse freigesetzt wird, was aber tatsächlich die Zellatmung ist."
         ], 0},
        {"Stellen Sie sich vor, Sie stehen an einem klaren Winterabend auf der Südhalbkugel der Erde und blicken in den Nachthimmel. Welches der folgenden astronomischen Objekte wäre unter diesen spezifischen Bedingungen mit bloßem Auge am deutlichsten und auffälligsten sichtbar?",
         [
           "Der Andromedanebel, unsere nächste große Nachbargalaxie, erscheint als verschwommener Lichtfleck im Sternbild Andromeda und befindet sich in etwa 2,5 Millionen Lichtjahren Entfernung von der Erde.",
           "Das Kreuz des Südens ist ein markantes, kompaktes Sternbild, das ausschließlich von der Südhalbkugel aus sichtbar ist und jahrhundertelang als wichtige Navigationshilfe für Seefahrer auf der Südhalbkugel diente.",
           "Der Polarstern kann aufgrund seiner Position nahe des nördlichen Himmelspols von der Südhalbkugel aus niemals über dem Horizont beobachtet werden und ist daher nicht sichtbar.",
           "Der Orionnebel ist eine riesige interstellare Gaswolke im Sternbild Orion, die als Geburtsstätte neuer Sterne dient und mit bloßem Auge als kleiner, verschwommener Fleck im Schwertgehänge des Orion zu erkennen ist."
         ], 1}
      ]
    }
  ]

  for topic_data <- topics_data do
    {:ok, topic} =
      %Topic{}
      |> Topic.changeset(%{name: topic_data.name, description: topic_data.description})
      |> Repo.insert()

    for {{prompt, options, correct}, q_idx} <- Enum.with_index(topic_data.questions) do
      {:ok, _question} =
        %Question{topic_id: topic.id}
        |> Question.changeset(%{
          prompt: prompt,
          options: Enum.map(options, &%{"text" => &1}),
          correct_index: correct,
          position: q_idx
        })
        |> Repo.insert()
    end
  end

  IO.puts("Seeded #{length(topics_data)} topics with questions.")
else
  IO.puts("Topics already exist, skipping seed.")
end
