//
// Copyright 2017 Christian Reitwiessner
// Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
//
// 2019 OKIMS
//      ported to solidity 0.6
//      fixed linter warnings
//      added requiere error messages
//
//
// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.14;

library PairingRotate {
    struct G1Point {
        uint256 X;
        uint256 Y;
    }
    // Encoding of field elements is: X[0] * z + X[1]

    struct G2Point {
        uint256[2] X;
        uint256[2] Y;
    }
    /// @return the generator of G1

    function P1() internal pure returns (G1Point memory) {
        return G1Point(1, 2);
    }
    /// @return the generator of G2

    function P2() internal pure returns (G2Point memory) {
        // Original code point
        return G2Point(
            [
                11559732032986387107991004021392285783925812861821192530917403151452391805634,
                10857046999023057135944570762232829481370756359578518086990519993285655852781
            ],
            [
                4082367875863433681332203403145435568316851327593401208105741076214120093531,
                8495653923123431417604973247489272438418190587263600148770280649306958101930
            ]
        );

        /*
        // Changed by Jordi point
        return G2Point(
            [10857046999023057135944570762232829481370756359578518086990519993285655852781,
             11559732032986387107991004021392285783925812861821192530917403151452391805634],
            [8495653923123431417604973247489272438418190587263600148770280649306958101930,
             4082367875863433681332203403145435568316851327593401208105741076214120093531]
        );*/
    }
    /// @return r the negation of p, i.e. p.addition(p.negate()) should be zero.

    function negate(G1Point memory p) internal pure returns (G1Point memory r) {
        // The prime q in the base field F_q for G1
        uint256 q = 21888242871839275222246405745257275088696311157297823662689037894645226208583;
        if (p.X == 0 && p.Y == 0) {
            return G1Point(0, 0);
        }
        return G1Point(p.X, q - (p.Y % q));
    }
    /// @return r the sum of two points of G1

    function addition(G1Point memory p1, G1Point memory p2)
        internal
        view
        returns (G1Point memory r)
    {
        uint256[4] memory input;
        input[0] = p1.X;
        input[1] = p1.Y;
        input[2] = p2.X;
        input[3] = p2.Y;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 6, input, 0xc0, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "pairing-add-failed");
    }
    /// @return r the product of a point on G1 and a scalar, i.e.
    /// p == p.scalar_mul(1) and p.addition(p) == p.scalar_mul(2) for all points p.

    function scalar_mul(G1Point memory p, uint256 s) internal view returns (G1Point memory r) {
        uint256[3] memory input;
        input[0] = p.X;
        input[1] = p.Y;
        input[2] = s;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success := staticcall(sub(gas(), 2000), 7, input, 0x80, r, 0x60)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "pairing-mul-failed");
    }
    /// @return the result of computing the pairing check
    /// e(p1[0], p2[0]) *  .... * e(p1[n], p2[n]) == 1
    /// For example pairing([P1(), P1().negate()], [P2(), P2()]) should
    /// return true.

    function pairing(G1Point[] memory p1, G2Point[] memory p2) internal view returns (bool) {
        require(p1.length == p2.length, "pairing-lengths-failed");
        uint256 elements = p1.length;
        uint256 inputSize = elements * 6;
        uint256[] memory input = new uint[](inputSize);
        for (uint256 i = 0; i < elements; i++) {
            input[i * 6 + 0] = p1[i].X;
            input[i * 6 + 1] = p1[i].Y;
            input[i * 6 + 2] = p2[i].X[0];
            input[i * 6 + 3] = p2[i].X[1];
            input[i * 6 + 4] = p2[i].Y[0];
            input[i * 6 + 5] = p2[i].Y[1];
        }
        uint256[1] memory out;
        bool success;
        // solium-disable-next-line security/no-inline-assembly
        assembly {
            success :=
                staticcall(sub(gas(), 2000), 8, add(input, 0x20), mul(inputSize, 0x20), out, 0x20)
            // Use "invalid" to make gas estimation work
            switch success
            case 0 { invalid() }
        }
        require(success, "pairing-opcode-failed");
        return out[0] != 0;
    }
    /// Convenience method for a pairing check for two pairs.

    function pairingProd2(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2
    ) internal view returns (bool) {
        G1Point[] memory p1 = new G1Point[](2);
        G2Point[] memory p2 = new G2Point[](2);
        p1[0] = a1;
        p1[1] = b1;
        p2[0] = a2;
        p2[1] = b2;
        return pairing(p1, p2);
    }
    /// Convenience method for a pairing check for three pairs.

    function pairingProd3(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        G1Point memory c1,
        G2Point memory c2
    ) internal view returns (bool) {
        G1Point[] memory p1 = new G1Point[](3);
        G2Point[] memory p2 = new G2Point[](3);
        p1[0] = a1;
        p1[1] = b1;
        p1[2] = c1;
        p2[0] = a2;
        p2[1] = b2;
        p2[2] = c2;
        return pairing(p1, p2);
    }
    /// Convenience method for a pairing check for four pairs.

    function pairingProd4(
        G1Point memory a1,
        G2Point memory a2,
        G1Point memory b1,
        G2Point memory b2,
        G1Point memory c1,
        G2Point memory c2,
        G1Point memory d1,
        G2Point memory d2
    ) internal view returns (bool) {
        G1Point[] memory p1 = new G1Point[](4);
        G2Point[] memory p2 = new G2Point[](4);
        p1[0] = a1;
        p1[1] = b1;
        p1[2] = c1;
        p1[3] = d1;
        p2[0] = a2;
        p2[1] = b2;
        p2[2] = c2;
        p2[3] = d2;
        return pairing(p1, p2);
    }
}

contract RotateVerifier {
    using PairingRotate for *;

    struct VerifyingKeyRotate {
        PairingRotate.G1Point alfa1;
        PairingRotate.G2Point beta2;
        PairingRotate.G2Point gamma2;
        PairingRotate.G2Point delta2;
        PairingRotate.G1Point[] IC;
    }

    struct ProofRotate {
        PairingRotate.G1Point A;
        PairingRotate.G2Point B;
        PairingRotate.G1Point C;
    }

    function verifyingKeyRotate() internal pure returns (VerifyingKeyRotate memory vk) {
        vk.alfa1 = PairingRotate.G1Point(
            20491192805390485299153009773594534940189261866228447918068658471970481763042,
            9383485363053290200918347156157836566562967994039712273449902621266178545958
        );

        vk.beta2 = PairingRotate.G2Point(
            [
                4252822878758300859123897981450591353533073413197771768651442665752259397132,
                6375614351688725206403948262868962793625744043794305715222011528459656738731
            ],
            [
                21847035105528745403288232691147584728191162732299865338377159692350059136679,
                10505242626370262277552901082094356697409835680220590971873171140371331206856
            ]
        );
        vk.gamma2 = PairingRotate.G2Point(
            [
                11559732032986387107991004021392285783925812861821192530917403151452391805634,
                10857046999023057135944570762232829481370756359578518086990519993285655852781
            ],
            [
                4082367875863433681332203403145435568316851327593401208105741076214120093531,
                8495653923123431417604973247489272438418190587263600148770280649306958101930
            ]
        );
         vk.delta2 = PairingRotate.G2Point(
            [11559732032986387107991004021392285783925812861821192530917403151452391805634,
             10857046999023057135944570762232829481370756359578518086990519993285655852781],
            [4082367875863433681332203403145435568316851327593401208105741076214120093531,
             8495653923123431417604973247489272438418190587263600148770280649306958101930]
        );
        vk.IC = new PairingRotate.G1Point[](66);
        
        vk.IC[0] = PairingRotate.G1Point( 
            885614313698455614762831514361474823558386273018973389257933241377161874465,
            13439447357969145123427823757632899503037233194962405933171630988347674369215
        );                                      
        
        vk.IC[1] = PairingRotate.G1Point( 
            5012789903342973774277471812303509057759038163184844208511042817470626880486,
            8465945711205257530431158932927571307796436515778805455908839143264569824162
        );                                      
        
        vk.IC[2] = PairingRotate.G1Point( 
            20899949897322196861412839734288499069476615759507166703925076396168090954584,
            1019775670512386666403897820948466911287029995210510401013780842740647420286
        );                                      
        
        vk.IC[3] = PairingRotate.G1Point( 
            1322090913716206021784858521638429890995899707258474352041313200202416739142,
            3519571895292569144672265473916892205301862181738485479062723152536929509261
        );                                      
        
        vk.IC[4] = PairingRotate.G1Point( 
            14719200358972756824255412780187638086272811075532713771467348279644151317828,
            16426106568849082335947538896034958105687377342074410096996119188545578892619
        );                                      
        
        vk.IC[5] = PairingRotate.G1Point( 
            3014980420138450386141478037224839886171071311791566372124399512119622502280,
            5414333023967496743710275047931013150786493660497358775533257499156591690770
        );                                      
        
        vk.IC[6] = PairingRotate.G1Point( 
            4955712412380685071752068323316120486209937042838336813124940524674817842029,
            12729828476922086761993841925144219216956809581857612815333382459197296112911
        );                                      
        
        vk.IC[7] = PairingRotate.G1Point( 
            3546803065235496508103291235766473314172682772703022385131360966649622948417,
            17967080051058184281934821271924505351271833830031424720435680781654913430991
        );                                      
        
        vk.IC[8] = PairingRotate.G1Point( 
            10861779766111816424112982540754086979871463358302921181139636589022513092256,
            11660528790202188743384774452876359345820176693590928467601363136552745985465
        );                                      
        
        vk.IC[9] = PairingRotate.G1Point( 
            1496206906492405246442479693554332784481400105149318380310060606311094951079,
            11140909699383961630106202034695091189966622126451911227434457446648913032195
        );                                      
        
        vk.IC[10] = PairingRotate.G1Point( 
            20251552989258536152245327630988403427289026981699126148890766979042930893920,
            528097876085387590550576366319970425951527216508997277014113723190159303438
        );                                      
        
        vk.IC[11] = PairingRotate.G1Point( 
            367880357770356156721706874733222142978799131853624221905731167909546693919,
            12433554591307135004156899095890982931243992479912578790619826315495764038388
        );                                      
        
        vk.IC[12] = PairingRotate.G1Point( 
            9584190858125794026559841124655878838343133523461196483579058953905627156037,
            6761519002730223843737691370990520542606191666968902518947722909554763766967
        );                                      
        
        vk.IC[13] = PairingRotate.G1Point( 
            21703024515562114953450366156068236370536517707568748596886195237663145452959,
            3327253125286457946442228363290503787389177603072496046444935262468171594419
        );                                      
        
        vk.IC[14] = PairingRotate.G1Point( 
            1136535400314212666226345245364167384908969793317697690715673675595615104884,
            6759635835171422321751927196094037956225725399953809647778160764325144090625
        );                                      
        
        vk.IC[15] = PairingRotate.G1Point( 
            1464863985504584260597237372735170130754880776472132828536258615632704515303,
            10021136849645905617069752728751835413935533996884037682529510230967572965192
        );                                      
        
        vk.IC[16] = PairingRotate.G1Point( 
            17288804410796646931286212878145311607762221998233413252358991280056091290258,
            7094452016624785057796791546112040692250160301480508166231604108797377449659
        );                                      
        
        vk.IC[17] = PairingRotate.G1Point( 
            375780278233514042671224260563221634968114690648765830349338272380436424849,
            6016170033990267577414305778663644390556159131170038289430152402676678034093
        );                                      
        
        vk.IC[18] = PairingRotate.G1Point( 
            2355406146220439638693796633546471566616913107201784689265786077416783554198,
            17929167114933064413575470198478465453038083519238972638317508129353205535762
        );                                      
        
        vk.IC[19] = PairingRotate.G1Point( 
            18417770925767645539512767912824544244265221606038074330579218558797485046115,
            9300167592320275842193935293239918984889411179634311329995877053805375061924
        );                                      
        
        vk.IC[20] = PairingRotate.G1Point( 
            6969699477656407716996901296660204320453501942695424828717762452986637231656,
            5994368949386856084676342708690186427785595851448247849502044009334310471416
        );                                      
        
        vk.IC[21] = PairingRotate.G1Point( 
            8725015952293872811409862937579601945051150574942288940772075726266434942993,
            19650937004872902457751735412111168652461619582995628435431152834390713288514
        );                                      
        
        vk.IC[22] = PairingRotate.G1Point( 
            1801190358822427016872260968725378100695508764529382035101634809307506990604,
            17508468087270948937572034238885007177695918992119513961747771485796286916793
        );                                      
        
        vk.IC[23] = PairingRotate.G1Point( 
            13045060805136677828122002532597337929864485032441782438310646549284586344582,
            21266107144983248829673159250982940426040278040575274079711203151945705963428
        );                                      
        
        vk.IC[24] = PairingRotate.G1Point( 
            5131252437054231485158107702441148081276022078275352950245923753434474648761,
            11005706609402239649228179947649544474068064448615867769291169263428886041828
        );                                      
        
        vk.IC[25] = PairingRotate.G1Point( 
            18375019218103300037112175062947231656533819628707920465190068893795226241013,
            13788400394913691380668230331245917694770116546324140668092016661630262700523
        );                                      
        
        vk.IC[26] = PairingRotate.G1Point( 
            21881389181014155111834065469035978493057283354557166398198526396037057726373,
            21746523645969724341816822834168073229814351646129880177387525582905072969018
        );                                      
        
        vk.IC[27] = PairingRotate.G1Point( 
            2466576772442974366689343968465212549705661019397906206616470083579840115521,
            9198763044947762520401397421446295958117844843308854371755437348614832765079
        );                                      
        
        vk.IC[28] = PairingRotate.G1Point( 
            21744734719248762909764705188584072733076852138014125889392024295230376132165,
            11008540229916025195413553223666089662398578607174023741526545045088636349496
        );                                      
        
        vk.IC[29] = PairingRotate.G1Point( 
            5175749149682611879386233570636451407089859526528101802789745142047342170993,
            19784469949704233906408549914760777841196427576122779073754561167894866454181
        );                                      
        
        vk.IC[30] = PairingRotate.G1Point( 
            4302610790320871983279224230850506525585532256629481303638272258974932088134,
            16162805687289048659348174883009707303191830289316864169674259033057633730474
        );                                      
        
        vk.IC[31] = PairingRotate.G1Point( 
            15036948972080786678096784517447888467003998703176744149150237040567282340752,
            2241295326908919442972869328160594250736735263993576508599863635062551784722
        );                                      
        
        vk.IC[32] = PairingRotate.G1Point( 
            13887020034535693620937554035713960013699877260962415018033449127137662870548,
            13236916858804903864420267898724404199585543739284741805831525246221359154958
        );                                      
        
        vk.IC[33] = PairingRotate.G1Point( 
            6995233164643211969842164722364369416535522264429402337837985567526941246998,
            8151624917988501460855119969083157474930142360261436737057570823660627564528
        );                                      
        
        vk.IC[34] = PairingRotate.G1Point( 
            6916217258042714717595533233792226148465195314122178136416911641575760358831,
            5505909885620199401893596526325074048438687917681395651170493087243513684964
        );                                      
        
        vk.IC[35] = PairingRotate.G1Point( 
            515305769689528464541924817583825095167045681555987425344518441478785754560,
            19655939261591597802322742585634582091652320672343847424776687354406271888812
        );                                      
        
        vk.IC[36] = PairingRotate.G1Point( 
            10707125114144213461672754526158918049667287846152821714444897601494784648705,
            138958670314520680477490302448248758736819119806320604585551775174521125229
        );                                      
        
        vk.IC[37] = PairingRotate.G1Point( 
            10918129695110039220058084082783566591429038666440154619903203577863582646257,
            2922122668401577853046960011039251205762056863803931671501936945474372957985
        );                                      
        
        vk.IC[38] = PairingRotate.G1Point( 
            4496080887176664743673861588428549798724159870663852459846604003885104018725,
            13821165481803379598248325001710461433829473788950101472278202239112145591971
        );                                      
        
        vk.IC[39] = PairingRotate.G1Point( 
            4256281743633544029781164285960335691674326588473651796228334694685318976145,
            4693163838680887086137379880806596513234854310803695693459898141706532476662
        );                                      
        
        vk.IC[40] = PairingRotate.G1Point( 
            19303710288835532097940942294298005719814663310690352715892870245787395356838,
            12574956102469644411509236073211206035564522502841214467867785771093265990746
        );                                      
        
        vk.IC[41] = PairingRotate.G1Point( 
            15328189963746669917830471971070500575255655227880381056494005322161399971120,
            8951252776770752653750258143484345783847879468334450119985396678968313729325
        );                                      
        
        vk.IC[42] = PairingRotate.G1Point( 
            7929800913777060624095641312156327037498550983927147280407829254816363808068,
            1910861175724374131636125342172363575690899602081186099283609304958432438832
        );                                      
        
        vk.IC[43] = PairingRotate.G1Point( 
            12849727197389303083543766442917681856560547379877494661343436017136104216492,
            2349511474853924097807140552884121213503719255719950179027840427457201092516
        );                                      
        
        vk.IC[44] = PairingRotate.G1Point( 
            18110827016446882391304397958168481563532884104522841162678711499438257001766,
            18441795859735067860918023582675462379098295173677502098824076220418223432256
        );                                      
        
        vk.IC[45] = PairingRotate.G1Point( 
            8312405445865571792360858722492124045608572698286430947005526652405891569779,
            17875948564807574671703361303501494543057298806479411639260593119893122892872
        );                                      
        
        vk.IC[46] = PairingRotate.G1Point( 
            21739700915798066634573344859784472455996356644166570293403931262711087222581,
            3431106461492133682464729380064560788280147680032446789642968549591674949169
        );                                      
        
        vk.IC[47] = PairingRotate.G1Point( 
            17976538026065867432739106893971053157257736170017540789062703443354567792161,
            441635732938732811495127072695226418720961542996494358931067602554458423616
        );                                      
        
        vk.IC[48] = PairingRotate.G1Point( 
            4192848686779367992734275396556496366076994133759768625421974276008243060560,
            20352344262956791242514786683835857766904264122847474740282612538685302841963
        );                                      
        
        vk.IC[49] = PairingRotate.G1Point( 
            21679442330323526455423822622177325594304039843052463602562907349964344641777,
            5999118605727283650588054345504517339597092460307021142633164822590187112186
        );                                      
        
        vk.IC[50] = PairingRotate.G1Point( 
            18051997462552659412739436870533992733315139211872799769366107912512558915508,
            19921207380547139434301474459982473874594370205058953660769532613073033074544
        );                                      
        
        vk.IC[51] = PairingRotate.G1Point( 
            17215940420850981780567041924675594246115442721695014953717621190451943123160,
            8205773367981728843402809496141318631488559318728893059573755858068193314171
        );                                      
        
        vk.IC[52] = PairingRotate.G1Point( 
            978038152196867495154309885019976263414755390058220632249783152775365951512,
            13036598774500541535871181871872969596822442798022283129312915702755171774022
        );                                      
        
        vk.IC[53] = PairingRotate.G1Point( 
            13122228780585253447288177200550914120442311591166809756626394064758277383284,
            16067511607848952159135941107441977711548931732674907985893242770241934769285
        );                                      
        
        vk.IC[54] = PairingRotate.G1Point( 
            387597278260473333800895717340096969762383478678670874534996014459259052117,
            8102523094342575243890610254493053954590285776923742899215331543909601067476
        );                                      
        
        vk.IC[55] = PairingRotate.G1Point( 
            58536627440582092559995586712184606701542170478534224695098940449709664402,
            16539934989662206163440694488250307070086711463087614915934935515925974319706
        );                                      
        
        vk.IC[56] = PairingRotate.G1Point( 
            17067175261760883830948156472717022753711868364649866480641567431344348609951,
            5221299197337403191557213582435788967412187361676060877376845535934560503197
        );                                      
        
        vk.IC[57] = PairingRotate.G1Point( 
            13354970124193478182063609306113799656824339920550031235874140027946510902753,
            981873192179032498372434668583678519615846259996698679294187034393310562669
        );                                      
        
        vk.IC[58] = PairingRotate.G1Point( 
            1615446824714332695134164561207369258123464657093237449683036076563290156989,
            9772573681088162948567555596332164259169989400472615839016679968240648456920
        );                                      
        
        vk.IC[59] = PairingRotate.G1Point( 
            21651137963615474258348989834547156077248117107595844463634058827622402550177,
            14938495547856204264120275255000524616695173053717583714168457956323756767782
        );                                      
        
        vk.IC[60] = PairingRotate.G1Point( 
            7348612000329346607913777211582998317116248409378393742599766029650555184448,
            16800266651217739521199261548189062144892208724004299626742351923835764349714
        );                                      
        
        vk.IC[61] = PairingRotate.G1Point( 
            3228916078220419477112780533322289324524911778896056547996143863873764133535,
            1994337234710765847242568869784264541329826720692079721208660436181113748729
        );                                      
        
        vk.IC[62] = PairingRotate.G1Point( 
            3230032602365351084594411465968674330930334583855871035671331603384429882277,
            17751389900717806004058773266700107496786182001266750235741408504315393668299
        );                                      
        
        vk.IC[63] = PairingRotate.G1Point( 
            3835598095578052973384142235131214969283803250574434789326248957438105932157,
            12129698627405900744720205599606405667506499744861081121425013458097313114692
        );                                      
        
        vk.IC[64] = PairingRotate.G1Point( 
            13140826234888709999979840464137523685152533239103774182476283991811991840378,
            6126793018950560331044562667099196124023330532461068082872610973653333845894
        );                                      
        
        vk.IC[65] = PairingRotate.G1Point( 
            5999817439787184191177539505452728580209776035165666946216625848554868296536,
            21063579144389317432327623508023948866223512963204350102711442289582068051
        );
    }

    function verifyRotate(uint256[] memory input, ProofRotate memory proof)
        internal
        view
        returns (uint256)
    {
        uint256 snark_scalar_field =
            21888242871839275222246405745257275088548364400416034343698204186575808495617;
        VerifyingKeyRotate memory vk = verifyingKeyRotate();
        require(input.length + 1 == vk.IC.length, "verifier-bad-input");
        // Compute the linear combination vk_x
        PairingRotate.G1Point memory vk_x = PairingRotate.G1Point(0, 0);
        for (uint256 i = 0; i < input.length; i++) {
            require(input[i] < snark_scalar_field, "verifier-gte-snark-scalar-field");
            vk_x = PairingRotate.addition(vk_x, PairingRotate.scalar_mul(vk.IC[i + 1], input[i]));
        }
        vk_x = PairingRotate.addition(vk_x, vk.IC[0]);
        if (
            !PairingRotate.pairingProd4(
                PairingRotate.negate(proof.A),
                proof.B,
                vk.alfa1,
                vk.beta2,
                vk_x,
                vk.gamma2,
                proof.C,
                vk.delta2
            )
        ) return 1;
        return 0;
    }
    /// @return r  bool true if proof is valid

    function verifyProofRotate(
        uint256[2] memory a,
        uint256[2][2] memory b,
        uint256[2] memory c,
        uint256[65] memory input
    ) public view returns (bool r) {
        ProofRotate memory proof;
        proof.A = PairingRotate.G1Point(a[0], a[1]);
        proof.B = PairingRotate.G2Point([b[0][0], b[0][1]], [b[1][0], b[1][1]]);
        proof.C = PairingRotate.G1Point(c[0], c[1]);
        uint256[] memory inputValues = new uint[](input.length);
        for (uint256 i = 0; i < input.length; i++) {
            inputValues[i] = input[i];
        }
        if (verifyRotate(inputValues, proof) == 0) {
            return true;
        } else {
            return false;
        }
    }
}
