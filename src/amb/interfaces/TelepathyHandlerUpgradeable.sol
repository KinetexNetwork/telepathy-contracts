pragma solidity ^0.8.0;

import {ITelepathyHandler} from "src/amb/interfaces/ITelepathy.sol";
import {Initializable} from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

abstract contract TelepathyHandlerUpgradeable is ITelepathyHandler, Initializable {
    error NotFromTelepathyRouter(address sender);

    address public telepathyRouter;

    function __TelepathyHandler_init(address _telepathyRouter) public onlyInitializing {
        telepathyRouter = _telepathyRouter;
    }

    function handleTelepathy(uint32 _sourceChainId, address _sourceAddress, bytes memory _data)
        external
        override
        returns (bytes4)
    {
        if (msg.sender != telepathyRouter) {
            revert NotFromTelepathyRouter(msg.sender);
        }
        handleTelepathyImpl(_sourceChainId, _sourceAddress, _data);
        return ITelepathyHandler.handleTelepathy.selector;
    }

    function handleTelepathyImpl(uint32 _sourceChainId, address _sourceAddress, bytes memory _data)
        internal
        virtual;
}
