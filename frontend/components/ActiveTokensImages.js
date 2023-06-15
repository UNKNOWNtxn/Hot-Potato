import React, { useEffect } from 'react';
import { useContractRead, useContractEvent } from 'wagmi';
import TokenImage from './TokenImage';

const ActiveTokensImages = ({ ownerAddress, ABI, shouldRefresh, tokenId }) => {

  useContractEvent({
    address: '0x09ED17Ad25F9d375eB24aa4A3C8d23D625D0aF7a',
    abi: ABI,
    eventName: 'PotatoMinted',
    async listener(log) {
      try {
        await refetchImageString({ args: [tokenId] });
        await refetchPotatoTokenId();
      } catch (error) {
        console.error('Error updating mints', error);
      }
    },
  });

  const { data: activeTokens, isLoading, refetch: refetchActiveTokens, isError } = useContractRead({
    address: '0x09ED17Ad25F9d375eB24aa4A3C8d23D625D0aF7a',
    abi: ABI,
    functionName: 'getActiveTokensOfOwner',
    args: [ownerAddress],
    enabled: true
  });


  const { data: getImageString, isLoading: loadingImage, refetch: refetchImageString, isError: errorImage } = useContractRead({
    address: '0x09ED17Ad25F9d375eB24aa4A3C8d23D625D0aF7a',
    abi: ABI,
    functionName: 'getImageString',
    args: [tokenId],
    enabled: true
  });

  useEffect(() => {
    refetchActiveTokens({ args: [ownerAddress] });
  }, [ownerAddress, refetchActiveTokens, shouldRefresh]);

  useEffect(() => {
    refetchActiveTokens({ args: [ownerAddress] });
  }, []);

  if (isLoading) {
    return <div>Loading...</div>;
  }

  if (!activeTokens) {
    console.log('Error loading active tokens', isError);
    return (
      <div className='flex flex-col'>
        <p>Error loading active tokens.{' '}</p>
        <button className='border-t-emerald-900 font-bold' onClick={() => refetchActiveTokens({ args: [ownerAddress] })}>
          Try Refreshing
        </button>
      </div>
    );
  }

  return (
    <div className={`grid grid-cols-3 sm:grid-cols-5 md:grid-cols-5 gap-4 justify-center items-center`}>
      {activeTokens.map((tokenId, index) => {
        return (
          <div key={index} className="border rounded-lg p-2 text-center justify-center items-center flex flex-col">
            <TokenImage tokenId={Number(tokenId)} ABI={ABI} shouldRefresh={shouldRefresh} size={300} />
          </div>
        );
      })}
    </div>
  );

};

export default ActiveTokensImages;
